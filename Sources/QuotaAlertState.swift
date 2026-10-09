import Foundation
import CryptoKit

struct QuotaAlert: Equatable {
    let key: String
    let reset: Double
    let threshold: Int
    let remaining: Int
    let label: String
    var identifier: String { "quota-\(key)-\(Int(reset))-\(threshold)" }
}

/// Persist only accepted notifications. Failed delivery may be retried on a later refresh.
struct QuotaAlertState: Codable {
    struct Cycle: Codable {
        var reset: Double
        var notified: Set<Int>
    }
    private var cycles: [String: Cycle] = [:]

    mutating func pending(for limits: Limits, at now: Date) -> [QuotaAlert] {
        cycles = cycles.filter { $0.value.reset > now.timeIntervalSince1970 }
        guard let bucket = limits.codex else { return [] }
        let account = limits.accountId ?? "local-account"
        return [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, window in
            guard let window, window.usedPercent.isFinite,
                  (0...100).contains(window.usedPercent), let reset = window.resetsAt,
                  reset.isFinite, reset > now.timeIntervalSince1970,
                  reset < Double(Int.max) else { return nil }
            let key = SHA256.hash(data: Data("\(account)|\(slot)|\(window.windowDurationMins ?? 0)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            if cycles[key]?.reset != reset { cycles[key] = Cycle(reset: reset, notified: []) }
            let remaining = 100 - window.usedPercent
            let threshold: Int
            if remaining < 10 { threshold = 10 }
            else if remaining < 20 { threshold = 20 }
            else { return nil }
            guard cycles[key]?.notified.contains(threshold) == false else { return nil }
            return QuotaAlert(key: key, reset: reset, threshold: threshold,
                              remaining: window.remaining, label: window.label)
        }
    }

    mutating func delivered(_ alert: QuotaAlert) {
        guard cycles[alert.key]?.reset == alert.reset else { return }
        cycles[alert.key]?.notified.insert(alert.threshold)
        // A jump straight below 10% replaces the less urgent 20% alert.
        if alert.threshold == 10 { cycles[alert.key]?.notified.insert(20) }
    }
}
