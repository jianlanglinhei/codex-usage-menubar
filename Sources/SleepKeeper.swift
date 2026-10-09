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
    private(set) var deadline: Date?
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
    static func thermalLevel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return tr("正常", "Normal")
        case .fair: return tr("偏热", "Warm")
        case .serious: return tr("高温", "Hot")
        case .critical: return tr("严重过热", "Critical")
        @unknown default: return tr("未知", "Unknown")
        }
    }
    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        tr("系统热状态：", "Thermal state: ") + thermalLevel(state)
    }
    var thermalStatus: String { Self.thermalText(ProcessInfo.processInfo.thermalState) }
    private func renewLease() {
        guard let marker, expectedOn else { return }
        if Self.shouldSleep(for: ProcessInfo.processInfo.thermalState) {
            overheatTriggered = true
            message = tr("过热保护已触发：正在恢复睡眠并请求休眠", "Overheat protection triggered: restoring sleep and requesting sleep now")
        }
        // Latch the signal until the watchdog handles it, even if the temperature drops.
        let signal = overheatTriggered ? "overheat" : "normal"
        do { try Data(signal.utf8).write(to: marker, options: .atomic) }
        catch { message = tr("保护状态无法更新，防休眠将在租约到期后关闭", "Couldn't update the safety lease; keep-awake will end when it expires") }
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
        if busy { return tr("正在更改合盖模式…", "Changing lid-closed mode…") }
        guard let enabled = Self.systemSleepDisabled() else { return tr("无法读取系统睡眠状态", "Couldn't read the system sleep state") }
        if enabled, let deadline {
            let minutes = max(0, Int(ceil(deadline.timeIntervalSinceNow / 60)))
            return tr("合盖继续工作：已开启（剩余 \(minutes) 分钟）", "Keep working with lid closed: on (\(minutes) min left)")
        }
        return enabled ? tr("系统已禁用睡眠（外部设置）", "Sleep disabled by another setting")
            : tr("合盖继续工作：关闭", "Keep working with lid closed: off")
    }
    init() {
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.renewLease()
            self.onChange?()
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
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
                    self.message = self.overheatTriggered ? Self.cooledDownMessage : Self.restoredMessage
                }
            }
            self.onChange?()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
    private static var cooledDownMessage: String { tr("过热保护已触发；请冷却后手动开启", "Overheat protection triggered; turn it on again after the Mac cools down") }
    private static var restoredMessage: String { tr("已恢复正常睡眠", "Normal sleep restored") }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptSource(command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let prompt = tr("Codex 额度工具需要临时调整睡眠设置，让合盖后的任务继续运行。",
                        "Codex Cub needs to change sleep settings temporarily so tasks keep running with the lid closed.")
        return "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
    }
    static func watchdogScript(pid: Int32, marker: String, seconds: Int = 7200) -> String {
        """
        marker=\(quote(marker))
        overheated=0
        fail() {
          printf 'CODEX_USAGE_ERROR:%s\\n' "$1"
          exit 1
        }
        check_battery() {
          battery=$(LC_ALL=C /usr/bin/pmset -g batt) || return 2
          case "$battery" in
            *"Battery Power"*)
              percent=$(printf '%s\\n' "$battery" | /usr/bin/awk -F ';' '/InternalBattery/ { sub(/.*[[:space:]]/, "", $1); gsub(/%/, "", $1); print $1 }')
              case "$percent" in ''|*[!0-9]*) return 2 ;; esac
              [ "$percent" -gt 20 ] || return 1
              ;;
            *"AC Power"*) ;;
            *) return 2 ;;
          esac
        }
        cleanup() {
          /usr/bin/pmset -a disablesleep 0 || return 1
          if [ "$overheated" = 1 ]; then /usr/bin/pmset sleepnow; fi
        }
        trap '' HUP
        trap 'exit 0' INT TERM
        [ -f "$marker" ] || fail lease
        /bin/kill -0 \(pid) 2>/dev/null || fail app
        check_battery || fail "battery:$?"
        trap cleanup EXIT
        /usr/bin/pmset -a disablesleep 1 || fail pmset
        started=$(/bin/date +%s)
        end=$(( started + \(seconds) ))
        # Close the authorization pipe only after reporting a successful start.
        printf 'CODEX_USAGE_READY\\n'
        exec >/dev/null 2>&1
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
          check_battery || break
          /bin/sleep 2
        done
        """
    }
    static func launchCommand(script: String) -> String {
        // Keep stdout attached for the startup acknowledgement. The watchdog closes it
        // before its monitoring loop so AppleScript doesn't wait for the full session.
        // No nohup: under administrator privileges it can't detach from the console and exits
        // without running the script. An ignored HUP is inherited by the background shell instead.
        "trap '' HUP; /bin/sh -c \(quote(script)) </dev/null 2>&1 &"
    }
    static func startupFailure(_ output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        if lines.contains("CODEX_USAGE_READY") { return nil }
        if lines.contains("CODEX_USAGE_ERROR:battery:1") {
            return tr("电池电量 ≤20%，请接通电源后重试", "Battery is at or below 20%. Connect power and try again.")
        }
        if lines.contains("CODEX_USAGE_ERROR:battery:2") {
            return tr("无法读取电脑电量，为保证低电量保护，未开启", "Couldn't read the battery level; keep-awake wasn't enabled to preserve battery protection.")
        }
        if lines.contains("CODEX_USAGE_ERROR:pmset") {
            return tr("系统拒绝修改睡眠设置，请重试管理员授权", "macOS rejected the sleep setting change. Try administrator authorization again.")
        }
        if lines.contains("CODEX_USAGE_ERROR:lease") || lines.contains("CODEX_USAGE_ERROR:app") {
            return tr("保护进程无法访问本次运行记录，请重启应用后重试", "The safety process couldn't access this session. Restart the app and try again.")
        }
        return tr("保护进程未能启动，请重试；详情见 sleep-startup.log", "The safety process couldn't start. Try again; details are in sleep-startup.log.")
    }
    func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = tr("合盖继续工作", "Keep Working with Lid Closed")
        alert.informativeText = text
        alert.addButton(withTitle: tr("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func runAuthorized(_ command: String) -> String? {
        var error: NSDictionary?
        NSApp.activate(ignoringOtherApps: true)
        let result = NSAppleScript(source: Self.appleScriptSource(command: command))?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            message = code == -128 ? tr("已取消，睡眠设置未更改", "Cancelled; sleep settings unchanged") : tr("系统未能更改睡眠设置", "macOS couldn't change sleep settings")
            if code != -128 { alert(error[NSAppleScript.errorMessage] as? String ?? tr("授权失败，请重试。", "Authorization failed. Try again.")) }
            return nil
        }
        return result?.stringValue
    }
    func start() {
        guard !busy else { return }
        guard Self.systemSleepDisabled() == false else {
            alert(tr("系统睡眠已被其他设置关闭，或状态无法读取。请先恢复正常睡眠，再开启本工具的限时模式。",
                     "Sleep is already disabled by another setting, or its state can't be read. Restore normal sleep first, then turn on the timed mode."))
            return
        }
        guard !Self.shouldSleep(for: ProcessInfo.processInfo.thermalState) else {
            alert(tr("当前系统热状态过高，请冷却后再开启合盖继续工作。", "Your Mac is too hot. Let it cool down before turning this on."))
            return
        }
        busy = true
        overheatTriggered = false
        message = nil
        onChange?()
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("codexusage-awake-\(UUID().uuidString)")
        do { try Data("normal".utf8).write(to: marker, options: .atomic) }
        catch { busy = false; alert(tr("无法创建本次运行记录：", "Couldn't create the session record: ") + error.localizedDescription); onChange?(); return }
        self.marker = marker
        let script = Self.watchdogScript(pid: ProcessInfo.processInfo.processIdentifier, marker: marker.path)
        let output = runAuthorized(Self.launchCommand(script: script))
        if let output {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodexUsage")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? "\(Date())\n\(output)\n".write(to: directory.appendingPathComponent("sleep-startup.log"), atomically: true, encoding: .utf8)
            message = Self.startupFailure(output)
        }
        // Authorization may take longer than the watchdog lease. Renew before it starts checking.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: marker.path)
        if output != nil, message == nil {
            deadline = Date().addingTimeInterval(7200)
            expectedOn = true
            renewLease()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.busy = false
                if !self.active {
                    self.message = self.overheatTriggered ? Self.cooledDownMessage
                        : tr("保护进程启动后已退出，睡眠保持开启；请重试", "The safety process exited after starting. Normal sleep remains enabled; try again.")
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
            catch { busy = false; alert(tr("无法停止本次运行：", "Couldn't stop this session: ") + error.localizedDescription); onChange?(); return }
        } else {
            _ = runAuthorized("/usr/bin/pmset -a disablesleep 0")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.busy = false
            if self.active {
                // The lease is already removed; expose administrator recovery if restoration failed.
                self.marker = nil
                self.message = tr("系统尚未恢复，请点击恢复正常睡眠", "Sleep isn't restored yet. Turn the switch off again to restore it.")
            } else { self.message = Self.restoredMessage; self.marker = nil }
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
