import AppKit
import Combine
import Foundation
import ServiceManagement

enum BarStyle: String, CaseIterable, Identifiable {
    case iconAndPercent, percent, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndPercent: return tr("图标和百分比", "Icon and percentage")
        case .percent: return tr("仅百分比", "Percentage only")
        case .icon: return tr("仅图标", "Icon only")
        }
    }
}

struct SleepDisplay {
    var active: Bool
    var busy: Bool
    var status: String
    var message: String?
    var deadline: Date?
}

final class UsageModel: ObservableObject {
    static let refreshInterval: TimeInterval = 300
    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexUsage")

    @Published private(set) var limits: Limits?
    @Published private(set) var error: String?
    @Published private(set) var fetching = false
    @Published private(set) var lastUpdate: Date?
    @Published var barStyle = BarStyle(rawValue: UserDefaults.standard.string(forKey: "barStyle") ?? "") ?? .iconAndPercent {
        didSet { UserDefaults.standard.set(barStyle.rawValue, forKey: "barStyle") }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginNote: String?
    /// Lets the panel close itself before a system prompt takes focus.
    var dismissPanel: (() -> Void)?

    let forecast: ResetForecastSource
    private let sleepKeeper: SleepKeeper?
    private var sleepPreview: SleepDisplay?
    private let live: Bool

    init() {
        live = true
        forecast = ResetForecastSource()
        sleepKeeper = SleepKeeper()
        sleepKeeper?.onChange = { [weak self] in self?.changed() }
        forecast.onChange = { [weak self] in self?.changed() }
        try? FileManager.default.createDirectory(at: Self.dataDirectory, withIntermediateDirectories: true)
    }

    /// Fixture state for offscreen snapshots; never reaches Codex, the network or pmset.
    init(preview limits: Limits?, error: String?, updated: Date?, forecast: ResetForecastSource, sleep: SleepDisplay, fetching: Bool = false) {
        live = false
        self.limits = limits
        self.error = error
        self.lastUpdate = updated
        self.forecast = forecast
        self.fetching = fetching
        sleepKeeper = nil
        sleepPreview = sleep
    }

    var windows: [Window] { limits?.codex?.windows ?? [] }
    var tightest: Window? { windows.min { $0.remaining < $1.remaining } }
    var stale: Bool { error != nil || (lastUpdate.map { Date().timeIntervalSince($0) > 600 } ?? true) }
    var sleep: SleepDisplay {
        if let sleepPreview { return sleepPreview }
        guard let keeper = sleepKeeper else { return SleepDisplay(active: false, busy: false, status: "", message: nil, deadline: nil) }
        return SleepDisplay(active: keeper.active, busy: keeper.busy, status: keeper.status, message: keeper.message, deadline: keeper.deadline)
    }

    private func changed() {
        objectWillChange.send()
        writeDiagnostic()
    }

    func refresh() {
        guard live else { return }
        forecast.refresh()
        guard !fetching else { return }
        fetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try fetchLimits() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                switch result {
                case .success(let data):
                    self.limits = data
                    self.lastUpdate = Date()
                    self.error = data.codex?.windows.isEmpty == false ? nil : tr("账户未返回 Codex 额度", "Your account returned no Codex limits")
                case .failure(let error):
                    if case FetchError.message(let message) = error { self.error = message }
                    else { self.error = tr("读取失败：", "Couldn't read limits: ") + error.localizedDescription }
                }
                self.writeDiagnostic()
            }
        }
    }

    /// Opening the panel should never show numbers older than a couple of minutes.
    func refreshIfStale() {
        if fetching { return }
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 120, error == nil { return }
        refresh()
    }

    func toggleSleep() {
        guard let keeper = sleepKeeper, !keeper.busy else { return }
        dismissPanel?()
        // The authorization prompt is modal; let the popover finish closing first.
        DispatchQueue.main.async { keeper.active ? keeper.stop() : keeper.start() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard live else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginNote = SMAppService.mainApp.status == .requiresApproval
                ? tr("需要在“系统设置 › 通用 › 登录项”里允许", "Allow it in System Settings › General › Login Items") : nil
        } catch {
            launchAtLoginNote = tr("无法更改登录项：", "Couldn't change login item: ") + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openDataDirectory() { NSWorkspace.shared.open(Self.dataDirectory) }

    func releaseLease() { sleepKeeper?.releaseLease() }

    var thermalState: ProcessInfo.ThermalState { sleepPreview == nil ? ProcessInfo.processInfo.thermalState : .nominal }
    var thermalStatus: String { sleepKeeper?.thermalStatus ?? SleepKeeper.thermalText(.nominal) }

    private func writeDiagnostic() {
        guard live else { return }
        let state = sleep
        let diagnostic = "\(forecast.diagnostic) thermal=\(thermalStatus) sleep=\(state.status) remaining=\(tightest.map { String($0.remaining) } ?? "nil") style=\(barStyle.rawValue) updated=\(String(describing: lastUpdate)) error=\(error ?? "none")\n"
        try? diagnostic.write(to: Self.dataDirectory.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    }
}
