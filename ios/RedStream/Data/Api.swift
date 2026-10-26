import Foundation

struct ApiError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Thin client for the RedStream backend's JSON API (the same endpoints the
/// TV web app uses). Auth is the bearer token from device approval; the
/// active profile travels as X-Profile-ID.
final class Api: @unchecked Sendable {
    private let prefs: Prefs
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    let userAgent: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "RedStream-iOS/1 (iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion))"
    }()

    init(prefs: Prefs) {
        self.prefs = prefs
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // /api/live/resolve can take a while
        session = URLSession(configuration: config)
    }

    var baseUrl: String { (prefs.baseUrl ?? "").trimmingTrailingSlashes }

    /// Normalizes what the user typed into the setup screen.
    func normalizeBaseUrl(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlashes
        if s.isEmpty { return nil }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "http://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url.absoluteString.trimmingTrailingSlashes
    }

    /// Absolute URL for a backend path (or an already absolute URL).
    func absolute(_ pathOrUrl: String?) -> URL? {
        guard let p = pathOrUrl, !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") { return URL(string: p) }
        return URL(string: baseUrl + (p.hasPrefix("/") ? p : "/" + p))
    }

    func authHeaders(withProfile: Bool = true) -> [String: String] {
        var h = ["User-Agent": userAgent]
        if let t = prefs.token { h["Authorization"] = "Bearer \(t)" }
        if withProfile, let p = prefs.profileId { h["X-Profile-ID"] = String(p) }
        return h
    }

    // MARK: Plumbing

    private func makeURL(_ path: String, _ params: [String: Any?], base: String?) throws -> URL {
        guard var comps = URLComponents(string: (base ?? baseUrl) + path) else {
            throw ApiError(status: 0, message: "Ungültige Server-Adresse")
        }
        let items = params.compactMap { k, v -> URLQueryItem? in
            guard let v = v else { return nil }
            let s = "\(v)"
            return s.isEmpty ? nil : URLQueryItem(name: k, value: s)
        }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw ApiError(status: 0, message: "Ungültige Server-Adresse") }
        return url
    }

    @discardableResult
    private func call(
        _ method: String,
        _ path: String,
        params: [String: Any?] = [:],
        body: [String: Any]? = nil,
        withProfile: Bool = true,
        base: String? = nil
    ) async throws -> Data {
        var req = URLRequest(url: try makeURL(path, params, base: base))
        req.httpMethod = method
        for (k, v) in authHeaders(withProfile: withProfile) { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method == "POST" || method == "PUT" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ApiError(status: status, message: msg ?? "Fehler \(status)")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, _ params: [String: Any?] = [:], withProfile: Bool = true) async throws -> T {
        try decoder.decode(T.self, from: try await call("GET", path, params: params, withProfile: withProfile))
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: Any], withProfile: Bool = true) async throws -> T {
        try decoder.decode(T.self, from: try await call("POST", path, body: body, withProfile: withProfile))
    }

    // MARK: Setup / auth

    /// Checks that `base` is a RedStream server.
    func probe(_ base: String) async throws {
        try await call("GET", "/api/auth/check", withProfile: false, base: base)
    }

    func requestAccess() async throws -> AccessRequest {
        try await post("/api/webapp/request-access", [:], withProfile: false)
    }

    func pollAccess(_ deviceId: String) async throws -> AccessPoll {
        try await get("/api/webapp/request-access/" + deviceId.pathEscaped, withProfile: false)
    }

    func profiles() async throws -> [Profile] {
        (try await get("/api/profiles", withProfile: false) as ProfilesResponse).profiles ?? []
    }

    // MARK: Browse

    func rail(_ path: String) async throws -> [BrowseItem] {
        (try await get(path) as ResultsResponse).results ?? []
    }

    func allByKind(_ kind: BrowseKind, page: Int, genre: String?) async throws -> PagedResponse {
        try await get(kind.endpoint, ["page": page, "per_page": 30, "genre": genre])
    }

    func search(_ keyword: String, site: String) async throws -> [BrowseItem] {
        (try await post("/api/search", ["keyword": keyword, "site": site], withProfile: false) as ResultsResponse).results ?? []
    }

    // MARK: Series

    func series(_ url: String) async throws -> SeriesDetail { try await get("/api/series", ["url": url]) }

    func seasons(_ url: String) async throws -> [Season] {
        (try await get("/api/seasons", ["url": url]) as SeasonsResponse).seasons ?? []
    }

    func episodes(_ seasonUrl: String) async throws -> [Episode] {
        (try await get("/api/episodes", ["url": seasonUrl]) as EpisodesResponse).episodes ?? []
    }

    func providers(_ episodeUrl: String) async throws -> [String: [String]] {
        (try await get("/api/providers", ["url": episodeUrl]) as ProvidersResponse).providers ?? [:]
    }

    func preferredLanguage(_ seriesUrl: String) async throws -> String {
        (try await get("/api/preferred-language", ["series_url": seriesUrl]) as LanguageResponse).language ?? "German Dub"
    }

    func setSeriesLanguage(_ seriesUrl: String, _ language: String) async throws {
        try await call("PUT", "/api/series-language", body: ["url": seriesUrl, "language": language])
    }

    // MARK: Progress / watchlist

    func continueWatching() async throws -> [ProgressEntry] {
        (try await get("/api/progress", ["continue": 1, "limit": 20]) as ProgressListResponse).progress ?? []
    }

    func allProgress() async throws -> [ProgressEntry] {
        (try await get("/api/progress", ["limit": 500]) as ProgressListResponse).progress ?? []
    }

    func episodeProgress(_ episodeUrl: String) async throws -> ProgressEntry? {
        (try await get("/api/progress/" + episodeUrl.pathEscaped) as ProgressOneResponse).progress
    }

    func saveProgress(_ p: PlayItem, position: Double, duration: Double, completed: Bool) async throws {
        var body: [String: Any] = [
            "episode_url": p.episodeUrl,
            "series_title": p.seriesTitle,
            "series_url": p.seriesUrl,
            "season": p.season,
            "episode_number": p.episodeNumber,
            "position_seconds": position,
            "duration_seconds": duration,
            "completed": completed,
        ]
        if let t = p.episodeTitle { body["episode_title"] = t }
        try await call("POST", "/api/progress", body: body)
    }

    func watchlist() async throws -> [WatchlistItem] {
        (try await get("/api/watchlist") as WatchlistResponse).items ?? []
    }

    func inWatchlist(_ url: String) async throws -> Bool {
        (try await get("/api/watchlist/check", ["url": url]) as InListResponse).inList ?? false
    }

    func addToWatchlist(_ url: String, title: String, poster: String?) async throws {
        var body: [String: Any] = ["series_url": url, "series_title": title]
        if let poster = poster { body["poster_url"] = poster }
        try await call("POST", "/api/watchlist", body: body)
    }

    func removeFromWatchlist(_ url: String) async throws {
        try await call("DELETE", "/api/watchlist", body: ["series_url": url])
    }

    // MARK: Playback

    /// Path of a downloaded episode's playlist (host dropped, like the web app does).
    func downloadedStream(folder: String, season: Int, episode: Int) async throws -> String {
        let url = (try await get("/api/stream", ["folder": folder, "season": season, "episode": episode]) as StreamResponse).url
        guard let comps = URLComponents(string: url), comps.host != nil else { return url }
        return comps.percentEncodedPath + (comps.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    func liveStream(_ episodeUrl: String, language: String?, provider: String?) async throws -> LiveStream {
        var body: [String: Any] = ["episode_url": episodeUrl]
        if let language = language { body["language"] = language }
        if let provider = provider { body["provider"] = provider }
        return try await post("/api/live/resolve", body)
    }

    // MARK: Cast

    func screens() async throws -> [Screen] {
        (try await get("/api/cast/screens") as ScreensResponse).screens ?? []
    }

    func castCommand(_ screenId: String, _ body: [String: Any]) async throws {
        try await call("POST", "/api/cast/screens/" + screenId.pathEscaped + "/command", body: body)
    }
}

extension String {
    var trimmingTrailingSlashes: String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Escapes everything but unreserved characters (for one path segment).
    var pathEscaped: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
