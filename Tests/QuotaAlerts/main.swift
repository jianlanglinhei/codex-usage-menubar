import Foundation

let now = Date(timeIntervalSince1970: 1_800_000_000)
func limits(_ remaining: Double, reset: Double = 1_800_010_000, account: String = "a", secondary: Double? = nil) -> Limits {
    Limits(accountId: account, rateLimits: Bucket(
        primary: Window(usedPercent: 100 - remaining, windowDurationMins: 300, resetsAt: reset),
        secondary: secondary.map { Window(usedPercent: 100 - $0, windowDurationMins: 10080, resetsAt: reset) }, credits: nil), rateLimitsByLimitId: nil)
}
var state = QuotaAlertState()
assert(state.pending(for: limits(20), at: now).isEmpty)
let low = state.pending(for: limits(19), at: now)
assert(low.count == 1 && low[0].threshold == 20)
// Unaccepted notifications (permission denied or add failure) are not consumed.
assert(state.pending(for: limits(19), at: now) == low)
state.delivered(low[0])
assert(state.pending(for: limits(19), at: now).isEmpty)
assert(state.pending(for: limits(10), at: now).isEmpty)
let critical = state.pending(for: limits(9), at: now)
assert(critical.count == 1 && critical[0].threshold == 10)
state.delivered(critical[0])
state = try JSONDecoder().decode(QuotaAlertState.self, from: JSONEncoder().encode(state))
assert(state.pending(for: limits(0), at: now).isEmpty)
assert(state.pending(for: limits(18), at: now).isEmpty)
assert(state.pending(for: limits(9, account: "b"), at: now).count == 1)
assert(state.pending(for: limits(9, secondary: 19), at: now).count == 1)
assert(state.pending(for: limits(9, reset: 1_800_020_000), at: now).count == 1)
var direct = QuotaAlertState()
let jump = direct.pending(for: limits(5), at: now)
assert(jump.count == 1 && jump[0].threshold == 10)
direct.delivered(jump[0])
assert(direct.pending(for: limits(15), at: now).isEmpty)
assert(direct.pending(for: limits(5, reset: 1_800_000_000), at: now).isEmpty)
assert(direct.pending(for: limits(.nan), at: now).isEmpty)
assert(direct.pending(for: limits(-10), at: now).isEmpty)
assert(direct.pending(for: Limits(accountId: nil, rateLimits: Bucket(primary: Window(usedPercent: 90, windowDurationMins: 300, resetsAt: nil), secondary: nil, credits: nil), rateLimitsByLimitId: nil), at: now).isEmpty)
var both = QuotaAlertState()
assert(both.pending(for: limits(19, secondary: 9), at: now).count == 2)
print("PASS: thresholds, delivery retry, persistence, recovery, account/window isolation, reset, direct critical, invalid/expired/missing data")
