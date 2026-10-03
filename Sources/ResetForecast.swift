import AppKit
import Foundation

struct ForecastError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ResetForecast: Codable {
    let sourceName: String
    let sourceURL: String
    let sourceCheckedAt: Date
    let probability24h: Int
    let probability48h: Int
    let latestResetAt: Date
    let originalPostURL: String
    var forecastAt: Date?
    var fetchedAt: Date?
    var sourceDegraded: Bool?
    var baseDate: Date { forecastAt ?? sourceCheckedAt }
    var isValid: Bool {
        (0...100).contains(probability24h) && (0...100).contains(probability48h)
        && probability48h >= probability24h && latestResetAt <= sourceCheckedAt
        && baseDate <= sourceCheckedAt.addingTimeInterval(60)
    }
    func isFresh(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(baseDate)
        return isValid && age >= -60 && age <= 6 * 3600
            && now.timeIntervalSince(sourceCheckedAt) <= 6 * 3600
    }
    static let cacheURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsage/reset-forecast.json")
    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
    static func load() -> ResetForecast? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            guard let date = Self.date(text) else { throw ForecastError(message: "缓存时间无效") }
            return date
        }
        guard let data = try? Data(contentsOf: cacheURL), let snapshot = try? decoder.decode(Self.self, from: data), snapshot.isValid else { return nil }
        return snapshot
    }
    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.cacheURL, options: .atomic)
    }

    // Read only the site's published fields. Never execute scripts or interpret animated 0% as a forecast.
    static func parse(_ html: String, now: Date = Date()) throws -> ResetForecast {
        func capture(_ pattern: String, in text: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        func attribute(_ key: String, in tag: String) -> String? {
            capture("(?:^|\\s)" + NSRegularExpression.escapedPattern(for: key) + "\\s*=\\s*[\"']([^\"']*)[\"']", in: tag)
        }
        let regex = try NSRegularExpression(pattern: "<[^>]+>")
        // Exclude embedded application scripts so quoted HTML cannot masquerade as visible fields.
        let scripts = try NSRegularExpression(pattern: "<script\\b[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let visibleHTML = scripts.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let tags = regex.matches(in: visibleHTML, range: NSRange(visibleHTML.startIndex..., in: visibleHTML)).compactMap { match -> String? in
            guard let range = Range(match.range, in: visibleHTML) else { return nil }
            return String(visibleHTML[range])
        }
        func tag(_ id: String) -> String? { tags.first { attribute("data-testid", in: $0) == id } }
        func probability(_ id: String) -> Int? {
            guard let element = tag(id), let value = attribute("data-target-value", in: element) else { return nil }
            return Int(value)
        }
        guard let p24 = probability("probability-ring-24h"), let p48 = probability("probability-ring-48h"),
              let resetTag = tag("reset-exact-time"), let resetText = attribute("datetime", in: resetTag), let reset = date(resetText),
              let freshnessIndex = tags.firstIndex(where: { attribute("data-testid", in: $0) == "monitor-freshness" }),
              let checkedText = tags.dropFirst(freshnessIndex + 1).prefix(40).compactMap({ attribute("datetime", in: $0) }).first,
              let checked = date(checkedText) else { throw ForecastError(message: "来源页面结构已变化，暂不展示新预测") }
        // Keep the forecast's own timestamp separate from the monitor's newer health-check time.
        guard let snapshotHeader = capture(#"(snapshot:\$R\[\d+\]=\{status:"[^"]+",updatedAt:"[^"]+",forecastStatus:"[^"]+")"#, in: html),
              let modelTime = capture(#"updatedAt:"([^"]+)""#, in: snapshotHeader).flatMap(date),
              let forecastStatus = capture(#"forecastStatus:"([^"]+)""#, in: snapshotHeader),
              forecastStatus == "current" else { throw ForecastError(message: "来源未提供有效的当前预测") }
        let post = tags.first { attribute("data-testid", in: $0) == "reset-timeline-item" && attribute("data-kind", in: $0) == "confirmed" && attribute("data-datetime", in: $0).flatMap(date) == reset }
        let forecast = Self(sourceName: "Codex Reset Monitor", sourceURL: "https://codexreset.org/", sourceCheckedAt: checked,
                            probability24h: p24, probability48h: p48, latestResetAt: reset,
                            originalPostURL: post.flatMap { attribute("data-source-url", in: $0) } ?? "",
                            forecastAt: modelTime, fetchedAt: now,
                            sourceDegraded: capture(#"status:"([^"]+)""#, in: snapshotHeader) == "degraded")
        guard forecast.isValid, checked <= now.addingTimeInterval(300), modelTime <= now.addingTimeInterval(300) else {
            throw ForecastError(message: "来源概率或时间异常，保留上次有效数据")
        }
        return forecast
    }
}

final class ResetForecastMenu: NSObject {
    var onChange: (() -> Void)?
    private var snapshot = ResetForecast.load()
    private var fetching = false
    private var error: String?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "MM月dd日 HH:mm"
        return f
    }()
    var diagnostic: String {
        let state = fetching ? "fetching" : (error ?? "ok")
        return "forecast=\(snapshot?.probability24h.description ?? "nil")/\(snapshot?.probability48h.description ?? "nil") fresh=\(snapshot?.isFresh() ?? false) fetched=\(String(describing: snapshot?.fetchedAt)) state=\(state)"
    }
    @objc func refresh() {
        guard !fetching else { return }
        fetching = true
        onChange?()
        let request = URLRequest(url: URL(string: "https://codexreset.org/")!)
        session.dataTask(with: request) { [weak self] data, response, networkError in
            let result: Result<ResetForecast, Error> = Result {
                if let networkError { throw networkError }
                guard let response = response as? HTTPURLResponse else { throw ForecastError(message: "来源没有返回有效响应") }
                guard response.url?.scheme == "https", response.url?.host == "codexreset.org" else { throw ForecastError(message: "来源跳转异常，已停止更新") }
                guard response.statusCode == 200 else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let message = response.statusCode == 403 && body.contains("安全策略") ? "公司网络策略拦截了来源域名" : "来源读取失败（HTTP \(response.statusCode)）"
                    throw ForecastError(message: message)
                }
                guard let data, data.count <= 5_000_000, let html = String(data: data, encoding: .utf8) else { throw ForecastError(message: "来源页面无效或过大") }
                return try ResetForecast.parse(html)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                switch result {
                case .success(let value):
                    self.snapshot = value
                    self.error = nil
                    do { try value.save() } catch { self.error = "读取成功，但本地缓存保存失败" }
                case .failure(let failure): self.error = failure.localizedDescription
                }
                self.onChange?()
            }
        }.resume()
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Tibo 重置预测")
        menu.autoenablesItems = false
        func line(_ text: String) {
            let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        line("Tibo · @thsottiaux")
        line("额外统一重置 · 第三方试验性预测")
        menu.addItem(.separator())
        if let snapshot {
            if snapshot.isFresh() {
                line("预测基准后 24 小时：约 \(snapshot.probability24h)%")
                line("预测基准后 48 小时：约 \(snapshot.probability48h)%")
            } else { line("来源预测已过期，暂不显示概率") }
            line("预测基准：\(formatter.string(from: snapshot.baseDate))（本机时区）")
            line("来源检查：\(formatter.string(from: snapshot.sourceCheckedAt))（本机时区）")
            if let fetched = snapshot.fetchedAt { line("本机更新：\(formatter.string(from: fetched))（本机时区）") }
            line("来源记录的最近重置：\(formatter.string(from: snapshot.latestResetAt))")
            if snapshot.sourceDegraded == true { line("来源部分监测异常，预测仅供参考") }
            line("来源：\(snapshot.sourceName) · 非官方")
        } else { line("暂时没有可用预测数据") }
        if let error { line("更新失败：\(String(error.prefix(85)))") }
        line("每 5 分钟自动刷新，过期后隐藏概率")
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: fetching ? "正在刷新预测…" : "立即刷新预测", action: #selector(refresh), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !fetching
        menu.addItem(refreshItem)
        let live = NSMenuItem(title: "查看实时预测与依据…", action: #selector(openLive), keyEquivalent: "")
        live.target = self
        menu.addItem(live)
        let post = NSMenuItem(title: "查看最近重置原帖…", action: #selector(openPost), keyEquivalent: "")
        post.target = self
        post.isEnabled = postURL != nil
        menu.addItem(post)
        return menu
    }
    private var postURL: URL? {
        guard let value = snapshot?.originalPostURL, let url = URL(string: value), url.scheme == "https", url.host == "x.com", url.path.hasPrefix("/thsottiaux/status/") else { return nil }
        return url
    }
    @objc private func openLive() { NSWorkspace.shared.open(URL(string: "https://codexreset.org/")!) }
    @objc private func openPost() { if let url = postURL { NSWorkspace.shared.open(url) } }
}
