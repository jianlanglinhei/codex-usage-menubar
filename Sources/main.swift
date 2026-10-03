import AppKit
import Foundation
import Darwin

struct Window: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded(.down)) }
    var label: String {
        guard let mins = windowDurationMins else { return "额度" }
        if mins == 10080 { return "每周额度" }
        if mins % 1440 == 0 { return "\(mins / 1440) 天额度" }
        if mins % 60 == 0 { return "\(mins / 60) 小时额度" }
        return "\(mins) 分钟额度"
    }
}
struct Bucket: Decodable {
    let primary: Window?
    let secondary: Window?
    var windows: [Window] { [primary, secondary].compactMap { $0 } }
}
struct Limits: Decodable {
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?
    var codex: Bucket? { rateLimitsByLimitId?["codex"] ?? rateLimits }
}
enum FetchError: Error { case message(String) }

// Use the official local RPC so credentials remain managed by Codex.
func fetchLimits() throws -> Limits {
    let process = Process()
    let userHome = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [userHome.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw FetchError.message("未找到 Codex CLI，请先安装并登录")
    }
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["app-server", "--listen", "stdio://"]
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "\(userHome.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    process.environment = environment
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    defer {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_bar", "version": "1.0"]]])
    var buffer = Data()
    let deadline = Date().addingTimeInterval(25)
    let fd = output.fileHandleForReading.fileDescriptor
    while Date() < deadline {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 500) > 0 else { continue }
        let chunk = output.fileHandleForReading.availableData
        guard !chunk.isEmpty else { throw FetchError.message("Codex 连接已关闭") }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: 0..<newline)
            buffer.removeSubrange(0...newline)
            guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, [1, 2].contains(id), let error = message["error"] as? [String: Any] {
                throw FetchError.message(error["message"] as? String ?? "无法读取额度")
            }
            if message["id"] as? Int == 1 {
                try send(["method": "initialized", "params": [:]])
                try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
            } else if message["id"] as? Int == 2, let result = message["result"] {
                return try JSONDecoder().decode(Limits.self, from: JSONSerialization.data(withJSONObject: result))
            }
        }
    }
    throw FetchError.message("读取超时，请检查网络或 Codex 登录状态")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var timer: Timer?
    let sleepKeeper = SleepKeeper()
    let resetForecast = ResetForecastMenu()
    var fetching = false
    var lastUpdate: Date?
    var limits: Limits?
    var error: String?
    let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "MM月dd日 HH:mm"
        return f
    }()
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsage"), withIntermediateDirectories: true)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CodexUsage"
        item.isVisible = true
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        sleepKeeper.onChange = { [weak self] in self?.render() }
        resetForecast.onChange = { [weak self] in self?.render() }
        render()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func line(_ text: String, menu: NSMenu) {
        let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        row.isEnabled = false
        menu.addItem(row)
    }
    func action(_ title: String, _ selector: Selector, menu: NSMenu) {
        let row = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        row.target = self
        menu.addItem(row)
    }
    func batteryImage(remaining: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 27, height: 14), flipped: false) { _ in
            let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 1.25, width: 23, height: 11.5), xRadius: 3, yRadius: 3)
            NSColor.gray.setStroke()
            outline.lineWidth = 1.5
            outline.stroke()
            NSColor.gray.setFill()
            NSBezierPath(roundedRect: NSRect(x: 25, y: 5, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()
            if let remaining, remaining > 0 {
                let width = max(1, 19 * CGFloat(remaining) / 100)
                (remaining <= 10 ? NSColor.systemRed : (remaining <= 20 ? NSColor.systemYellow : NSColor.systemGreen)).setFill()
                NSBezierPath(roundedRect: NSRect(x: 2.75, y: 3.25, width: width, height: 7.5), xRadius: min(1.5, width / 2), yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Codex 剩余额度"
        return image
    }
    func render() {
        let windows = limits?.codex?.windows ?? []
        let stale = error != nil || (lastUpdate.map { Date().timeIntervalSince($0) > 600 } ?? true)
        let remaining = windows.map(\.remaining).min()
        item.button?.image = batteryImage(remaining: remaining)
        item.button?.title = remaining.map { " \($0)%\(stale ? " !" : "")" } ?? " —"
        item.button?.toolTip = "Codex 剩余额度" + (stale ? "（尚未更新或数据已过期）" : "")
        let menu = NSMenu()
        line("Codex 剩余额度", menu: menu)
        menu.addItem(.separator())
        if windows.isEmpty { line("暂无额度数据", menu: menu) }
        for window in windows {
            line("\(window.label)：剩余 \(window.remaining)%", menu: menu)
            if let reset = window.resetsAt {
                line("重置：\(dateFormatter.string(from: Date(timeIntervalSince1970: reset)))（本机时区）", menu: menu)
            }
        }
        if let reserve = limits?.rateLimitsByLimitId?["base_model_inference"]?.primary {
            line("备用模型额度：剩余 \(reserve.remaining)%", menu: menu)
        }
        menu.addItem(.separator())
        if let lastUpdate { line("更新：\(dateFormatter.string(from: lastUpdate))（本机时区）", menu: menu) }
        line("每 5 分钟自动刷新", menu: menu)
        if let error { line(String(error.prefix(100)), menu: menu) }
        action(fetching ? "正在刷新…" : "立即刷新", #selector(refresh), menu: menu)
        menu.addItem(.separator())
        let forecastItem = NSMenuItem(title: "Tibo 重置预测", action: nil, keyEquivalent: "")
        forecastItem.submenu = resetForecast.makeMenu()
        menu.addItem(forecastItem)
        let settingsMenu = NSMenu(title: "设置")
        settingsMenu.autoenablesItems = false
        line(sleepKeeper.status, menu: settingsMenu)
        line(sleepKeeper.thermalStatus, menu: settingsMenu)
        line("过热保护：合盖模式下，高温即请求休眠", menu: settingsMenu)
        if let message = sleepKeeper.message { line(message, menu: settingsMenu) }
        let sleepAction = NSMenuItem(title: sleepKeeper.active ? "关闭并恢复正常睡眠" : "开启合盖继续工作（2 小时）", action: #selector(toggleSleep), keyEquivalent: "")
        sleepAction.target = self
        sleepAction.isEnabled = !sleepKeeper.busy
        settingsMenu.addItem(sleepAction)
        line("电池 ≤20%、到时或退出后自动恢复", menu: settingsMenu)
        line("开启需要管理员授权；请放在通风处", menu: settingsMenu)
        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        action("退出", #selector(quit), menu: menu)
        item.menu = menu
        let diagnostic = "\(resetForecast.diagnostic) menu=\(menu.items.map(\.title)) thermal=\(sleepKeeper.thermalStatus) sleep=\(sleepKeeper.status) icon=battery title=\(item.button?.title ?? "nil") visible=\(item.isVisible) frame=\(String(describing: item.button?.window?.frame)) screens=\(NSScreen.screens.map { NSStringFromRect($0.frame) }) updated=\(String(describing: lastUpdate)) error=\(error ?? "none")\n"
        try? diagnostic.write(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsage/status.txt"), atomically: true, encoding: .utf8)
    }
    @objc func refresh() {
        resetForecast.refresh()
        guard !fetching else { return }
        fetching = true
        render()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try fetchLimits() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                switch result {
                case .success(let data):
                    self.limits = data
                    self.lastUpdate = Date()
                    self.error = data.codex?.windows.isEmpty == false ? nil : "账户未返回 Codex 额度"
                case .failure(let error):
                    if case FetchError.message(let message) = error { self.error = message }
                    else { self.error = "读取失败：\(error.localizedDescription)" }
                }
                self.render()
            }
        }
    }
    @objc func toggleSleep() {
        if sleepKeeper.active { sleepKeeper.stop() } else { sleepKeeper.start() }
    }
    func applicationWillTerminate(_ notification: Notification) { sleepKeeper.releaseLease() }
    @objc func quit() {
        sleepKeeper.releaseLease()
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--check") {
    do {
        let data = try fetchLimits()
        guard let windows = data.codex?.windows, !windows.isEmpty else { throw FetchError.message("No quota windows") }
        for window in windows { print("\(window.label): remaining=\(window.remaining)%") }
    } catch { fputs("\(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
