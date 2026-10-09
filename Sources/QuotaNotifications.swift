import Foundation
import UserNotifications

/// All state transitions run on the main queue, including asynchronous permission/delivery results.
final class QuotaNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var state: QuotaAlertState
    private var processing = false
    private var generation = 0
    private var latest: Limits?
    private var latestAt: Date?
    private let stateKey = "quotaAlertState.v1"
    var onNote: ((String?) -> Void)?
    var onOpen: (() -> Void)?
    var enabled: Bool { defaults.object(forKey: "quotaAlertsEnabled") as? Bool ?? true }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: "quotaAlertState.v1")
            .flatMap { try? JSONDecoder().decode(QuotaAlertState.self, from: $0) } ?? QuotaAlertState()
        super.init()
        center.delegate = self
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "quotaAlertsEnabled")
        generation += 1
        onNote?(nil)
        if !enabled {
            center.removeAllPendingNotificationRequests()
            return
        }
        if let latest, let latestAt, Date().timeIntervalSince(latestAt) <= 600 {
            record(latest, at: latestAt)
        }
    }

    func invalidate() {
        latest = nil
        latestAt = nil
        generation += 1
    }

    func record(_ limits: Limits, at now: Date) {
        latest = limits
        latestAt = now
        guard enabled, !processing else { return }
        var alerts = state.pending(for: limits, at: now)
        guard !alerts.isEmpty else { return }
        processing = true
        let currentGeneration = generation
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.enabled, self.generation == currentGeneration else { self.processing = false; return }
                guard granted else {
                    self.processing = false
                    self.onNote?(error == nil
                        ? tr("额度提醒未获系统授权，请在系统设置 › 通知中允许 Codex Cub", "Allow Codex Cub in System Settings › Notifications to receive quota alerts")
                        : tr("无法申请通知权限，请稍后重试", "Unable to request notification permission. Try again later."))
                    return
                }
                // Permission prompts can outlive the quota reading or reset boundary.
                guard let latest = self.latest, let latestAt = self.latestAt,
                      Date().timeIntervalSince(latestAt) <= 600 else { self.processing = false; return }
                alerts = self.state.pending(for: latest, at: Date())
                self.onNote?(nil)
                self.deliver(alerts, generation: currentGeneration)
            }
        }
    }

    private func deliver(_ alerts: [QuotaAlert], generation: Int) {
        guard enabled, self.generation == generation, let alert = alerts.first else { processing = false; return }
        guard alert.reset > Date().timeIntervalSince1970 else {
            deliver(Array(alerts.dropFirst()), generation: generation)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = tr("Codex 额度不足", "Codex quota running low")
        content.body = tr("\(alert.label)剩余 \(alert.remaining)%（低于 \(alert.threshold)%）。",
                          "\(alert.label): \(alert.remaining)% remaining (below \(alert.threshold)%).")
            + resetText(Date(timeIntervalSince1970: alert.reset))
        content.sound = .default
        center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if error == nil {
                    self.state.delivered(alert)
                    if let data = try? JSONEncoder().encode(self.state) { self.defaults.set(data, forKey: self.stateKey) }
                } else {
                    self.onNote?(tr("额度通知发送失败，下次刷新时重试", "Quota notification failed; will retry on the next refresh"))
                }
                self.deliver(Array(alerts.dropFirst()), generation: generation)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onOpen?(); completionHandler() }
    }
}
