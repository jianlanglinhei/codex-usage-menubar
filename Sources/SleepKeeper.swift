import AppKit
import Foundation
import IOKit

// This is a session-scoped watchdog, not a permanent privileged installation.
// The root process only executes fixed system commands; it never executes user-writable files.
final class SleepKeeper {
    var onChange: (() -> Void)?
    private(set) var busy = false
    private(set) var message: String?
    private var marker: URL?
    private var deadline: Date?
    private var pollTimer: Timer?
    private var expectedOn = false
    private var thermalObserver: NSObjectProtocol?
    private var overheatTriggered = false
    static func shouldSleep(for state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .nominal, .fair: return false
        case .serious, .critical: return true
        @unknown default: return true
        }
    }
    var thermalStatus: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "系统热状态：正常"
        case .fair: return "系统热状态：偏热"
        case .serious: return "系统热状态：高温"
        case .critical: return "系统热状态：严重过热"
        @unknown default: return "系统热状态：未知"
        }
    }
    private func renewLease() {
        guard let marker, expectedOn else { return }
        if Self.shouldSleep(for: ProcessInfo.processInfo.thermalState) {
            overheatTriggered = true
            message = "过热保护已触发：正在恢复睡眠并请求休眠"
        }
        // Latch the signal until the watchdog handles it, even if the temperature drops.
        let signal = overheatTriggered ? "overheat" : "normal"
        do { try Data(signal.utf8).write(to: marker, options: .atomic) }
        catch { message = "保护状态无法更新，防休眠将在租约到期后关闭" }
    }

    static func systemSleepDisabled() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return (IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.boolValue
    }
    var active: Bool { Self.systemSleepDisabled() == true }
    var owned: Bool { marker != nil }
    var status: String {
        if busy { return "正在更改合盖模式…" }
        guard let enabled = Self.systemSleepDisabled() else { return "无法读取系统睡眠状态" }
        if enabled, let deadline {
            return "合盖继续工作：已开启（剩余 \(max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))) 分钟）"
        }
        return enabled ? "系统已禁用睡眠（外部设置）" : "合盖继续工作：关闭"
    }
    init() {
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.renewLease()
            self.onChange?()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let marker = self.marker, self.expectedOn {
                if self.active {
                    // A stalled or crashed app stops renewing this lease; the root watchdog restores sleep.
                    self.renewLease()
                } else if !self.busy {
                    try? FileManager.default.removeItem(at: marker)
                    self.marker = nil
                    self.deadline = nil
                    self.expectedOn = false
                    self.message = self.overheatTriggered ? "过热保护已触发；请冷却后手动开启" : "已恢复正常睡眠"
                }
            }
            self.onChange?()
        }
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptSource(command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "do shell script \"\(escaped)\" with administrator privileges with prompt \"Codex 额度工具需要临时调整睡眠设置，让合盖后的任务继续运行。\""
    }
    static func watchdogScript(pid: Int32, marker: String, seconds: Int = 7200) -> String {
        """
        marker=\(quote(marker))
        overheated=0
        cleanup() {
          /usr/bin/pmset -a disablesleep 0 || return 1
          if [ "$overheated" = 1 ]; then /usr/bin/pmset sleepnow; fi
        }
        trap cleanup EXIT
        trap 'exit 0' HUP INT TERM
        [ -f "$marker" ] || exit 1
        /bin/kill -0 \(pid) 2>/dev/null || exit 1
        /usr/bin/pmset -a disablesleep 1 || exit 1
        started=$(/bin/date +%s)
        end=$(( started + \(seconds) ))
        while [ -f "$marker" ] && /bin/kill -0 \(pid) 2>/dev/null; do
          signal=$(/bin/cat "$marker") || break
          case "$signal" in
            overheat) overheated=1; break ;;
            normal) ;;
            *) break ;;
          esac
          now=$(/bin/date +%s)
          [ "$now" -lt "$end" ] || break
          modified=$(/usr/bin/stat -f %m "$marker" 2>/dev/null) || break
          if [ $((now - started)) -ge 10 ]; then
            [ $((now - modified)) -lt 45 ] || break
          fi
          battery=$(/usr/bin/pmset -g batt) || break
          case "$battery" in
            *"Battery Power"*)
              percent=$(echo "$battery" | /usr/bin/awk -F ';' '/InternalBattery/ { sub(/.*[[:space:]]/, "", $1); gsub(/%/, "", $1); print $1 }')
              case "$percent" in ''|*[!0-9]*) break ;; esac
              [ "$percent" -gt 20 ] || break
              ;;
          esac
          /bin/sleep 2
        done
        """
    }
    func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "合盖继续工作"
        alert.informativeText = text
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func runAuthorized(_ command: String) -> Bool {
        var error: NSDictionary?
        NSApp.activate(ignoringOtherApps: true)
        let result = NSAppleScript(source: Self.appleScriptSource(command: command))?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            message = code == -128 ? "已取消，睡眠设置未更改" : "系统未能更改睡眠设置"
            if code != -128 { alert(error[NSAppleScript.errorMessage] as? String ?? "授权失败，请重试。") }
            return false
        }
        return result != nil
    }
    func start() {
        guard !busy else { return }
        guard Self.systemSleepDisabled() == false else {
            alert("系统睡眠已被其他设置关闭，或状态无法读取。请先恢复正常睡眠，再开启本工具的限时模式。")
            return
        }
        guard !Self.shouldSleep(for: ProcessInfo.processInfo.thermalState) else {
            alert("当前系统热状态过高，请冷却后再开启合盖继续工作。")
            return
        }
        busy = true
        overheatTriggered = false
        message = nil
        onChange?()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("codexusage-awake-\(UUID().uuidString)")
        do { try Data("normal".utf8).write(to: marker, options: .atomic) }
        catch { busy = false; alert("无法创建本次运行记录：\(error.localizedDescription)"); onChange?(); return }
        self.marker = marker
        let script = Self.watchdogScript(pid: ProcessInfo.processInfo.processIdentifier, marker: marker.path)
        let command = "/usr/bin/nohup /bin/sh -c \(Self.quote(script)) </dev/null >/dev/null 2>&1 &"
        let accepted = runAuthorized(command)
        // Authorization may take longer than the watchdog lease. Renew before it starts checking.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: marker.path)
        if accepted {
            deadline = Date().addingTimeInterval(7200)
            expectedOn = true
            renewLease()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.busy = false
                if !self.active {
                    self.message = self.overheatTriggered ? "过热保护已触发；请冷却后手动开启" : "未能开启，或电脑电池已低于保护阈值"
                    try? FileManager.default.removeItem(at: marker)
                    self.marker = nil
                    self.deadline = nil
                    self.expectedOn = false
                } else if !self.overheatTriggered { self.message = nil }
                self.onChange?()
            }
        } else {
            try? FileManager.default.removeItem(at: marker)
            self.marker = nil
            busy = false
            onChange?()
        }
    }
    func stop() {
        guard !busy else { return }
        busy = true
        onChange?()
        if let marker {
            do { try FileManager.default.removeItem(at: marker) }
            catch { busy = false; alert("无法停止本次运行：\(error.localizedDescription)"); onChange?(); return }
        } else {
            _ = runAuthorized("/usr/bin/pmset -a disablesleep 0")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.busy = false
            if self.active {
                // The lease is already removed; expose administrator recovery if restoration failed.
                self.marker = nil
                self.message = "系统尚未恢复，请点击恢复正常睡眠"
            } else { self.message = "已恢复正常睡眠"; self.marker = nil }
            self.deadline = nil
            self.expectedOn = false
            self.onChange?()
        }
    }
    func releaseLease() {
        if let marker { try? FileManager.default.removeItem(at: marker) }
    }
    deinit {
        releaseLease()
        pollTimer?.invalidate()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
    }
}
