import Foundation
import Darwin

struct Window: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int { Int(max(0, min(100, 100 - usedPercent)).rounded(.down)) }
    var label: String {
        guard let mins = windowDurationMins else { return tr("额度", "Limit") }
        if mins == 10080 { return tr("每周额度", "Weekly limit") }
        if mins % 1440 == 0 { return tr("\(mins / 1440) 天额度", "\(mins / 1440)-day limit") }
        if mins % 60 == 0 { return tr("\(mins / 60) 小时额度", "\(mins / 60)-hour limit") }
        return tr("\(mins) 分钟额度", "\(mins)-minute limit")
    }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
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
    var reserve: Window? { rateLimitsByLimitId?["base_model_inference"]?.primary }
}
enum FetchError: Error { case message(String) }

enum QuotaLevel {
    case healthy, low, critical
    init(remaining: Int) { self = remaining <= 10 ? .critical : remaining <= 20 ? .low : .healthy }
}

/// "3 天 4 小时" / "3d 4h"; minutes only below an hour.
func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded(.up))
    if minutes <= 1 { return tr("不到 1 分钟", "<1 min") }
    if minutes < 60 { return tr("\(minutes) 分钟", "\(minutes) min") }
    let hours = minutes / 60, days = hours / 24
    if days > 0 {
        return hours % 24 == 0 ? tr("\(days) 天", "\(days)d") : tr("\(days) 天 \(hours % 24) 小时", "\(days)d \(hours % 24)h")
    }
    return minutes % 60 == 0 ? tr("\(hours) 小时", "\(hours)h") : tr("\(hours) 小时 \(minutes % 60) 分", "\(hours)h \(minutes % 60)m")
}

func resetText(_ date: Date, now: Date = Date()) -> String {
    let left = date.timeIntervalSince(now)
    if left <= 0 { return tr("已到重置时间，等待刷新", "Reset due, waiting for refresh") }
    return tr(durationText(left) + "后重置", "Resets in " + durationText(left))
}

func ageText(_ date: Date, now: Date = Date()) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return tr("刚刚更新", "Updated just now") }
    let age = durationText((seconds / 60).rounded(.down) * 60)
    return tr(age + "前更新", "Updated \(age) ago")
}

// Use the official local RPC so credentials remain managed by Codex.
func fetchLimits() throws -> Limits {
    let process = Process()
    let userHome = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [userHome.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw FetchError.message(tr("未找到 Codex CLI，请先安装并登录", "Codex CLI not found. Install it and sign in first."))
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
        guard !chunk.isEmpty else { throw FetchError.message(tr("Codex 连接已关闭", "Codex closed the connection")) }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: 0..<newline)
            buffer.removeSubrange(0...newline)
            guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, [1, 2].contains(id), let error = message["error"] as? [String: Any] {
                throw FetchError.message(error["message"] as? String ?? tr("无法读取额度", "Couldn't read usage limits"))
            }
            if message["id"] as? Int == 1 {
                try send(["method": "initialized", "params": [:]])
                try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
            } else if message["id"] as? Int == 2, let result = message["result"] {
                return try JSONDecoder().decode(Limits.self, from: JSONSerialization.data(withJSONObject: result))
            }
        }
    }
    throw FetchError.message(tr("读取超时，请检查网络或 Codex 登录状态", "Timed out. Check your network or Codex sign-in."))
}
