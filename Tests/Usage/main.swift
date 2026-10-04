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
