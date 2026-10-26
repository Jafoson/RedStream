import Foundation

/// "Auf TV abspielen": which TV (a browser running the web app, see
/// web/cast.py) is the playback target, and remote control for it.
/// No target selected = play on this phone.
@MainActor
final class CastController: ObservableObject {
    struct Target: Equatable {
        let id: String
        let name: String
    }

    private let api: Api
    private let prefs: Prefs

    @Published private(set) var target: Target?
    /// Latest heartbeat of `target` (nil while unknown / offline).
    @Published private(set) var targetScreen: Screen?
    @Published private(set) var targetOffline = false

    init(api: Api, prefs: Prefs) {
        self.api = api
        self.prefs = prefs
        if let id = prefs.castScreenId {
            target = Target(id: id, name: prefs.castScreenName ?? "Fernseher")
        }
    }

    func select(_ screen: Screen?) {
        target = screen.map { Target(id: $0.id, name: $0.name) }
        targetScreen = screen
        targetOffline = false
        prefs.castScreenId = screen?.id
        prefs.castScreenName = screen?.name
    }

    func screens() async throws -> [Screen] { try await api.screens() }

    /// Refreshes `targetScreen`; called periodically while the remote bar shows.
    func refreshTarget() async {
        guard let t = target else { return }
        let match = (try? await api.screens())?.first { $0.id == t.id }
        guard target == t else { return }
        targetScreen = match
        targetOffline = match == nil
    }

    func play(_ item: PlayItem) async throws {
        guard let t = target else { throw ApiError(status: 0, message: "Kein Fernseher ausgewählt") }
        var body: [String: Any] = [
            "type": "play",
            "episode_url": item.episodeUrl,
            "series_title": item.seriesTitle,
            "series_url": item.seriesUrl,
            "season": item.season,
            "episode_number": item.episodeNumber,
        ]
        if let v = item.episodeTitle { body["episode_title"] = v }
        if let v = item.absoluteEpisodeNumber { body["absolute_episode_number"] = v }
        if let v = item.language { body["language"] = v }
        if let v = item.provider { body["provider"] = v }
        try await api.castCommand(t.id, body)
    }

    func toggle() async { await simple("toggle") }
    func stop() async { await simple("stop") }

    func seek(by seconds: Int) async {
        guard let t = target else { return }
        try? await api.castCommand(t.id, ["type": "seek", "delta": seconds])
    }

    private func simple(_ type: String) async {
        guard let t = target else { return }
        try? await api.castCommand(t.id, ["type": type])
    }
}
