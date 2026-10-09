import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns download, signature verification, replacement and relaunch.
/// The app only provides the entry points and keeps its menu state in sync.
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = false
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var started = false

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var needsInstallation: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") || downloads.map { path.hasPrefix($0 + "/") } == true
    }

    func start() {
        guard !started else { return }
        guard !needsInstallation else { canCheck = true; return }
        do {
            try controller.updater.start()
            started = true
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        } catch {
            // Keep the entry available so a manual attempt can show an actionable error.
            canCheck = true
            NSLog("Updater startup failed: %@", error.localizedDescription)
        }
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        if needsInstallation {
            let alert = NSAlert()
            alert.messageText = tr("请先安装到应用程序", "Move the app to Applications first")
            alert.informativeText = tr("请将 CodexUsage.app 拖到「应用程序」后重新打开，再检查更新。", "Move CodexUsage.app to Applications and reopen it before checking for updates.")
            alert.addButton(withTitle: tr("好", "OK"))
            alert.runModal()
            return
        }
        start()
        guard started else {
            let alert = NSAlert()
            alert.messageText = tr("更新服务无法启动", "Unable to start the updater")
            alert.informativeText = tr("请重新打开 App 后重试，或从官网下载最新版。", "Reopen the app and try again, or download the latest version from the website.")
            alert.addButton(withTitle: tr("好", "OK"))
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        guard started else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct UpdateMenuItems: View {
    @ObservedObject var updater: AppUpdater
    var check: () -> Void

    var body: some View {
        Text("Codex Cub \(AppUpdater.version)")
        Button(tr("检查更新…", "Check for Updates…"), action: check).disabled(!updater.canCheck)
        Toggle(tr("自动检查更新", "Automatically check for updates"), isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks)).disabled(!updater.started)
    }
}
