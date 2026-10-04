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
            guard let date = Self.date(text) else { throw ForecastError(message: tr("缓存时间无效", "Cached time is invalid")) }
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
              let checked = date(checkedText) else { throw ForecastError(message: tr("来源页面结构已变化，暂不展示新预测", "The source page changed; new forecasts are hidden for now")) }
        // Keep the forecast's own timestamp separate from the monitor's newer health-check time.
        guard let snapshotHeader = capture(#"(snapshot:\$R\[\d+\]=\{status:"[^"]+",updatedAt:"[^"]+",forecastStatus:"[^"]+")"#, in: html),
              let modelTime = capture(#"updatedAt:"([^"]+)""#, in: snapshotHeader).flatMap(date),
              let forecastStatus = capture(#"forecastStatus:"([^"]+)""#, in: snapshotHeader),
              forecastStatus == "current" else { throw ForecastError(message: tr("来源未提供有效的当前预测", "The source has no current forecast")) }
        let post = tags.first { attribute("data-testid", in: $0) == "reset-timeline-item" && attribute("data-kind", in: $0) == "confirmed" && attribute("data-datetime", in: $0).flatMap(date) == reset }
        let forecast = Self(sourceName: "Codex Reset Monitor", sourceURL: "https://codexreset.org/", sourceCheckedAt: checked,
                            probability24h: p24, probability48h: p48, latestResetAt: reset,
                            originalPostURL: post.flatMap { attribute("data-source-url", in: $0) } ?? "",
                            forecastAt: modelTime, fetchedAt: now,
                            sourceDegraded: capture(#"status:"([^"]+)""#, in: snapshotHeader) == "degraded")
        guard forecast.isValid, checked <= now.addingTimeInterval(300), modelTime <= now.addingTimeInterval(300) else {
            throw ForecastError(message: tr("来源概率或时间异常，保留上次有效数据", "The source returned odd values; keeping the last valid forecast"))
        }
        return forecast
    }
}

final class ResetForecastSource {
    var onChange: (() -> Void)?
    private(set) var snapshot: ResetForecast?
    private(set) var fetching = false
    private(set) var error: String?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    init(snapshot: ResetForecast? = ResetForecast.load(), error: String? = nil) {
        self.snapshot = snapshot
        self.error = error
    }
    var diagnostic: String {
        let state = fetching ? "fetching" : (error ?? "ok")
        return "forecast=\(snapshot?.probability24h.description ?? "nil")/\(snapshot?.probability48h.description ?? "nil") fresh=\(snapshot?.isFresh() ?? false) fetched=\(String(describing: snapshot?.fetchedAt)) state=\(state)"
    }
    func refresh() {
        guard !fetching else { return }
        fetching = true
        onChange?()
        let request = URLRequest(url: URL(string: "https://codexreset.org/")!)
        session.dataTask(with: request) { [weak self] data, response, networkError in
            let result: Result<ResetForecast, Error> = Result {
                if let networkError { throw networkError }
                guard let response = response as? HTTPURLResponse else { throw ForecastError(message: tr("来源没有返回有效响应", "The source returned no valid response")) }
                guard response.url?.scheme == "https", response.url?.host == "codexreset.org" else { throw ForecastError(message: tr("来源跳转异常，已停止更新", "The source redirected unexpectedly; updates stopped")) }
                guard response.statusCode == 200 else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let message = response.statusCode == 403 && body.contains("安全策略") ? tr("公司网络策略拦截了来源域名", "Your network policy blocks the source site") : tr("来源读取失败（HTTP \(response.statusCode)）", "Couldn't load the source (HTTP \(response.statusCode))")
                    throw ForecastError(message: message)
                }
                guard let data, data.count <= 5_000_000, let html = String(data: data, encoding: .utf8) else { throw ForecastError(message: tr("来源页面无效或过大", "The source page is invalid or too large")) }
                return try ResetForecast.parse(html)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                switch result {
                case .success(let value):
                    self.snapshot = value
                    self.error = nil
                    do { try value.save() } catch { self.error = tr("读取成功，但本地缓存保存失败", "Loaded, but the local cache couldn't be saved") }
                case .failure(let failure): self.error = failure.localizedDescription
                }
                self.onChange?()
            }
        }.resume()
    }
    var postURL: URL? {
        guard let value = snapshot?.originalPostURL, let url = URL(string: value), url.scheme == "https", url.host == "x.com", url.path.hasPrefix("/thsottiaux/status/") else { return nil }
        return url
    }
    func openLive() { NSWorkspace.shared.open(URL(string: "https://codexreset.org/")!) }
    func openPost() { if let url = postURL { NSWorkspace.shared.open(url) } }
}
