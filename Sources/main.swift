import AppKit
import Combine
import SwiftUI

func batteryImage(remaining: Int?, stale: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 27, height: 14), flipped: false) { _ in
        let frame = NSColor.gray.withAlphaComponent(stale ? 0.55 : 1)
        let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 1.25, width: 23, height: 11.5), xRadius: 3, yRadius: 3)
        frame.setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
        frame.setFill()
        NSBezierPath(roundedRect: NSRect(x: 25, y: 5, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()
        if let remaining, remaining > 0 {
            let width = max(1, 19 * CGFloat(remaining) / 100)
            let fill: NSColor
            switch QuotaLevel(remaining: remaining) {
            case .healthy: fill = .systemGreen
            case .low: fill = .systemOrange
            case .critical: fill = .systemRed
            }
            fill.withAlphaComponent(stale ? 0.5 : 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 2.75, y: 3.25, width: width, height: 7.5), xRadius: min(1.5, width / 2), yRadius: 1.5).fill()
        }
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = tr("Codex 剩余额度", "Codex usage remaining")
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let model = UsageModel()
    private let popover = NSPopover()
    private var timer: Timer?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CodexUsage"
        item.isVisible = true
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let host = NSHostingController(rootView: UsagePanel(model: model, quit: { [weak self] in self?.quit() }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        model.dismissPanel = { [weak self] in self?.popover.performClose(nil) }
        observation = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.render() }
        render()
        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: UsageModel.refreshInterval, repeats: true) { [weak self] _ in self?.model.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func render() {
        guard let button = item.button else { return }
        let remaining = model.tightest?.remaining
        let stale = model.stale
        let percent = remaining.map { "\($0)%" } ?? "—"
        switch model.barStyle {
        case .iconAndPercent:
            button.image = batteryImage(remaining: remaining, stale: stale)
            button.title = " " + percent + (stale ? " !" : "")
        case .percent:
            button.image = nil
            button.title = percent + (stale ? " !" : "")
        case .icon:
            button.image = batteryImage(remaining: remaining, stale: stale)
            button.title = stale ? " !" : ""
        }
        var tip = tr("Codex 剩余额度 ", "Codex usage remaining: ") + percent
        if let window = model.tightest, let reset = window.resetDate { tip += tr("（\(window.label)，\(resetText(reset))）", " (\(window.label), \(resetText(reset).lowercased()))") }
        if stale { tip += tr("\n尚未更新或数据已过期", "\nNot updated yet or out of date") }
        button.toolTip = tip + tr("\n点按查看详情，右键快捷操作", "\nClick for details, right-click for quick actions")
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true { showQuickMenu() }
        else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refreshIfStale()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showQuickMenu() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let summary = NSMenuItem(title: model.tightest.map { tr("剩余 \($0.remaining)% · \($0.label)", "\($0.remaining)% left · \($0.label)") } ?? tr("暂无额度数据", "No usage data"), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        let open = NSMenuItem(title: tr("打开面板", "Open Panel"), action: #selector(openPanel), keyEquivalent: "")
        let refresh = NSMenuItem(title: model.fetching ? tr("正在刷新…", "Refreshing…") : tr("立即刷新", "Refresh Now"), action: #selector(refresh), keyEquivalent: "r")
        refresh.isEnabled = !model.fetching
        let quit = NSMenuItem(title: tr("退出", "Quit"), action: #selector(quit), keyEquivalent: "q")
        for row in [open, refresh] { row.target = self; menu.addItem(row) }
        menu.addItem(.separator())
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    func popoverDidShow(_ notification: Notification) { item.button?.highlight(true) }
    func popoverDidClose(_ notification: Notification) { item.button?.highlight(false) }

    @objc private func openPanel() { if !popover.isShown { togglePopover() } }
    @objc private func refresh() { model.refresh() }
    func applicationWillTerminate(_ notification: Notification) { model.releaseLease() }
    @objc private func quit() {
        model.releaseLease()
        NSApp.terminate(nil)
    }
}

/// Renders the panel with fixture data so layout changes can be reviewed without Codex, the network or pmset.
enum Snapshots {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let forecast = ResetForecast(sourceName: "Codex Reset Monitor", sourceURL: "https://codexreset.org/", sourceCheckedAt: now.addingTimeInterval(-900),
                                     probability24h: 18, probability48h: 34, latestResetAt: now.addingTimeInterval(-5 * 86400),
                                     originalPostURL: "https://x.com/thsottiaux/status/1", forecastAt: now.addingTimeInterval(-1200),
                                     fetchedAt: now.addingTimeInterval(-60), sourceDegraded: false)
        func limits(_ weekly: Double, _ short: Double) throws -> Limits {
            let buckets: [String: Any] = ["codex": ["primary": ["usedPercent": short, "windowDurationMins": 300, "resetsAt": now.addingTimeInterval(2 * 3600 + 1500).timeIntervalSince1970],
                                                    "secondary": ["usedPercent": weekly, "windowDurationMins": 10080, "resetsAt": now.addingTimeInterval(3 * 86400 + 4 * 3600).timeIntervalSince1970]]]
            return try JSONDecoder().decode(Limits.self, from: JSONSerialization.data(withJSONObject: ["rateLimitsByLimitId": buckets]))
        }
        let off = SleepDisplay(active: false, busy: false, status: "", message: nil, deadline: nil)
        let on = SleepDisplay(active: true, busy: false, status: "", message: nil, deadline: now.addingTimeInterval(97 * 60))
        let cases: [(String, NSAppearance.Name, UsageModel)] = [
            ("panel-light", .aqua, UsageModel(preview: try limits(38, 12), error: nil, updated: now.addingTimeInterval(-120), forecast: ResetForecastSource(snapshot: forecast), sleep: off)),
            ("panel-dark", .darkAqua, UsageModel(preview: try limits(38, 12), error: nil, updated: now.addingTimeInterval(-120), forecast: ResetForecastSource(snapshot: forecast), sleep: on)),
            ("panel-low-error", .aqua, UsageModel(preview: try limits(86, 93), error: tr("读取超时，请检查网络或 Codex 登录状态", "Timed out. Check your network or Codex sign-in."), updated: now.addingTimeInterval(-1500),
                                                  forecast: ResetForecastSource(snapshot: nil, error: tr("公司网络策略拦截了来源域名", "Your network policy blocks the source site")), sleep: off)),
            ("panel-loading", .aqua, UsageModel(preview: nil, error: nil, updated: nil, forecast: ResetForecastSource(snapshot: nil), sleep: off, fetching: true)),
        ]
        let icons = HStack(spacing: 18) {
            ForEach([(76, false), (16, false), (7, false), (62, true)], id: \.0) { remaining, stale in
                HStack(spacing: 3) {
                    Image(nsImage: batteryImage(remaining: remaining, stale: stale))
                    Text("\(remaining)%\(stale ? " !" : "")").font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            }
        }.padding(10)
        try write(icons, appearance: .aqua, to: directory.appendingPathComponent("menubar.png"))
        for (name, appearance, model) in cases {
            try write(UsagePanel(model: model), appearance: appearance, to: directory.appendingPathComponent(name + ".png"))
            print(directory.appendingPathComponent(name + ".png").path)
        }
    }

    private static func write<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) throws {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw FetchError.message("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw FetchError.message("no png") }
        try data.write(to: url)
    }
}

if CommandLine.arguments.contains("--check") {
    do {
        let data = try fetchLimits()
        guard let windows = data.codex?.windows, !windows.isEmpty else { throw FetchError.message("No quota windows") }
        for window in windows { print("\(window.label): remaining=\(window.remaining)%") }
    } catch { fputs("\(error)\n", stderr); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    if let flag = CommandLine.arguments.firstIndex(of: "--lang"), flag + 1 < CommandLine.arguments.count {
        Language.current = CommandLine.arguments[flag + 1].hasPrefix("zh") ? .chinese : .english
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    do { try Snapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { fputs("\(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
