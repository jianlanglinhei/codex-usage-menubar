import Foundation
let now = Date(timeIntervalSince1970: 1_800_000_000)

Language.current = .chinese
precondition(durationText(30) == "不到 1 分钟")
precondition(durationText(45 * 60) == "45 分钟")
precondition(durationText(2 * 3600 + 25 * 60) == "2 小时 25 分")
precondition(durationText(3 * 86400 + 4 * 3600) == "3 天 4 小时")
precondition(durationText(2 * 86400) == "2 天")
precondition(resetText(now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "3 天 4 小时后重置")
precondition(resetText(now.addingTimeInterval(-5), now: now) == "已到重置时间，等待刷新")
precondition(ageText(now.addingTimeInterval(-20), now: now) == "刚刚更新")
precondition(ageText(now.addingTimeInterval(-600), now: now) == "10 分钟前更新")
precondition(ageText(now.addingTimeInterval(-179), now: now) == "2 分钟前更新")
print("PASS Chinese countdown and age wording")

Language.current = .english
precondition(durationText(30) == "<1 min")
precondition(durationText(45 * 60) == "45 min")
precondition(durationText(2 * 3600 + 25 * 60) == "2h 25m")
precondition(durationText(3 * 86400 + 4 * 3600) == "3d 4h")
precondition(resetText(now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "Resets in 3d 4h")
precondition(ageText(now.addingTimeInterval(-20), now: now) == "Updated just now")
precondition(ageText(now.addingTimeInterval(-600), now: now) == "Updated 10 min ago")
print("PASS English countdown and age wording")

precondition(QuotaLevel(remaining: 21) == .healthy && QuotaLevel(remaining: 20) == .low && QuotaLevel(remaining: 10) == .critical)
print("PASS quota colour thresholds match the menu bar icon")
let json = #"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":88.6,"windowDurationMins":300},"secondary":{"usedPercent":-3,"windowDurationMins":10080}},"base_model_inference":{"primary":{"usedPercent":100}}}}"#
let limits = try JSONDecoder().decode(Limits.self, from: Data(json.utf8))
precondition(limits.codex?.windows.map(\.remaining) == [11, 100])
precondition(limits.codex?.windows.map(\.label) == ["5-hour limit", "Weekly limit"])
Language.current = .chinese
precondition(limits.codex?.windows.map(\.label) == ["5 小时额度", "每周额度"])
print("PASS limits decoding, clamping and labels in both languages")

func credits(_ json: String) throws -> Credits {
    try JSONDecoder().decode(Credits.self, from: Data(json.utf8))
}
let paid = try credits(#"{"hasCredits":true,"unlimited":false,"balance":"57806.9421142500"}"#)
precondition(paid.balance == Decimal(string: "57806.9421142500"))
precondition(paid.displayBalance == "57,806")
let zero = try credits(#"{"hasCredits":false,"unlimited":false,"balance":"0"}"#)
precondition(zero.displayBalance == "0")
for value in ["null", #""invalid""#, #""12junk""#, #""-1""#, "-1"] {
    let unavailable = try credits("{\"balance\":\(value)}")
    precondition(unavailable.balance == nil && unavailable.displayBalance == "暂无数据")
}
let unlimited = try credits(#"{"unlimited":true,"balance":null}"#)
precondition(unlimited.displayBalance == "不限量")
Language.current = .english
precondition(paid.displayBalance == "57,806" && unlimited.displayBalance == "Unlimited")
let legacy = try JSONDecoder().decode(Limits.self, from: Data(#"{"rateLimits":{"primary":{"usedPercent":100},"credits":{"balance":"57806","unlimited":false}}}"#.utf8))
precondition(legacy.codex?.windows.first?.remaining == 0)
precondition(legacy.codex?.credits?.displayBalance == "57,806")
precondition(limits.codex?.credits == nil)
let perBucket = try JSONDecoder().decode(Limits.self, from: Data(#"{"rateLimitsByLimitId":{"codex":{"credits":{"balance":"1234.5"}},"base_model_inference":{"credits":{"balance":"9999"}}}}"#.utf8))
precondition(perBucket.codex?.credits?.displayBalance == "1,234")
print("PASS credit balance: precision, zero, unavailable, unlimited, legacy and per-limit responses")

func sample(_ balance: String, account: String = "test-account", unlimited: Bool = false) throws -> Limits {
    let json = """
    {"accountId":"\(account)","rateLimits":{"primary":{"usedPercent":100},"credits":{"balance":\(balance),"unlimited":\(unlimited)}}}
    """
    return try JSONDecoder().decode(Limits.self, from: Data(json.utf8))
}
var activity = CreditActivity()
activity.record(try sample("100.75"), at: now)
precondition(!activity.isConsuming(at: now, stale: false)) // Exhaustion alone isn't spending.
activity.record(try sample("100.25"), at: now.addingTimeInterval(300))
precondition(activity.decrease == Decimal(string: "0.5"))
precondition(activity.isConsuming(at: now.addingTimeInterval(301), stale: false))
precondition(!activity.isConsuming(at: now.addingTimeInterval(301), stale: true))
precondition(!activity.isConsuming(at: now.addingTimeInterval(901), stale: false))
activity.record(try sample("100.25"), at: now.addingTimeInterval(400))
precondition(!activity.isConsuming(at: now.addingTimeInterval(400), stale: false))
activity.record(try sample("200"), at: now.addingTimeInterval(500))
precondition(activity.decrease == nil) // Top-ups/reset don't count as consumption.
activity.record(try sample("50", account: "other-account"), at: now.addingTimeInterval(600))
precondition(activity.decrease == nil)
activity.record(try sample("49", account: "other-account"), at: now.addingTimeInterval(1300))
precondition(activity.decrease == nil) // A long sleep leaves no recent activity evidence.
activity.record(try sample("null", account: "other-account"), at: now.addingTimeInterval(1400))
activity.record(try sample("20", account: "other-account"), at: now.addingTimeInterval(1500))
precondition(activity.decrease == nil)
activity.record(try sample("10", account: "other-account", unlimited: true), at: now.addingTimeInterval(1600))
precondition(activity.decrease == nil)
print("PASS observed credit usage: decline, first read, unchanged, top-up, account switch, stale, missing and unlimited")
