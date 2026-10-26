import Combine
import Foundation

/// "Auf TV abspielen": which TV is the playback target, and remote control
/// for it. Two kinds of TV:
/// - a RedStream screen: a browser running the web app (see web/cast.py),
///   controlled through the server; remembered across launches;
/// - a Google Cast device (Chromecast, Android TV), see `GoogleCastManager`.
/// No target = play on this phone (which may itself be AirPlaying to an Apple TV).
@MainActor
final class CastController: ObservableObject {
    enum Kind { case screen, gcast }

    struct Target: Equatable {
        let id: String
        let name: String
        var kind: Kind = .screen
    }

    private let api: Api
    private let prefs: Prefs
    let gcast = GoogleCastManager()

    @Published private var screenTarget: Target?
    @Published private var screenState: Screen?
    @Published private var screenOffline = false
    /// What the Cast device plays (it only knows a URL and a title).
    @Published private var gcastItem: PlayItem?
    private var bag = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?

    /// A connected Cast device wins over the remembered screen.
    var target: Target? {
        if let name = gcast.connected { return Target(id: "gcast", name: name, kind: .gcast) }
        return screenTarget
    }

    /// Latest state of `target` for the remote bar (nil while unknown).
    var targetScreen: Screen? {
        guard let name = gcast.connected else { return screenState }
        let item = gcastItem
        return Screen(
            id: "gcast",
            name: name,
            profileId: nil,
            profileName: nil,
            state: ScreenState(
                status: item == nil ? "idle" : gcast.playerState,
                seriesTitle: item?.seriesTitle,
                season: item?.season,
                episodeNumber: item?.episodeNumber,
                position: gcast.position,
                duration: gcast.duration
            )
        )
    }

    var targetOffline: Bool { gcast.connected == nil && screenOffline }

    init(api: Api, prefs: Prefs) {
        self.api = api
        self.prefs = prefs
        if let id = prefs.castScreenId {
            screenTarget = Target(id: id, name: prefs.castScreenName ?? "Fernseher")
        }
        // Views observe this controller; pass the Cast manager's changes on.
        gcast.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        // A Cast device doesn't report to the server — save its progress from here.
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self = self, let item = self.gcastItem, self.gcast.connected != nil,
                      self.gcast.playerState == "playing", self.gcast.duration > 0 else { continue }
                let pos = self.gcast.position
                let dur = self.gcast.duration
                try? await self.api.saveProgress(item, position: pos, duration: dur, completed: pos / dur >= 0.9)
            }
        }
    }

    func select(_ screen: Screen?) {
        if gcast.connected != nil { gcast.disconnect() }
        screenTarget = screen.map { Target(id: $0.id, name: $0.name) }
        screenState = screen
        screenOffline = false
        prefs.castScreenId = screen?.id
        prefs.castScreenName = screen?.name
    }

    func connectGcast(_ device: GoogleCastManager.Device) {
        screenTarget = nil
        prefs.castScreenId = nil
        prefs.castScreenName = nil
        gcast.connect(device)
    }

    func screens() async throws -> [Screen] { try await api.screens() }

    /// Refreshes a RedStream screen's state; called periodically while the remote bar shows.
    func refreshTarget() async {
        guard let t = screenTarget, gcast.connected == nil else { return }
        let match = (try? await api.screens())?.first { $0.id == t.id }
        guard screenTarget == t else { return }
        screenState = match
        screenOffline = match == nil
    }

    func play(_ item: PlayItem) async throws {
        if gcast.connected != nil {
            let url = try await loginFreeURL(item)
            var resume = 0.0
            if let p = try? await api.episodeProgress(item.episodeUrl), !p.isCompleted,
               p.position > 30, p.position < p.duration - 10 {
                resume = p.position
            }
            gcastItem = item
            gcast.load(
                url: url,
                title: item.seriesTitle,
                subtitle: epCode(item.season, item.episodeNumber) + (item.episodeTitle.map { " · " + $0 } ?? ""),
                start: resume
            )
            return
        }
        guard let t = screenTarget else { throw ApiError(status: 0, message: "Kein Fernseher ausgewählt") }
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

    /// A URL the TV can fetch without logging in: /api/share for a
    /// downloaded episode, else the direct-stream relay.
    private func loginFreeURL(_ item: PlayItem) async throws -> URL {
        var folder = item.folder
        if folder == nil,
           let season = try? await api.seasons(item.seriesUrl).first(where: { $0.seasonNumber == item.season }),
           let ep = try? await api.episodes(season.url).first(where: { $0.url == item.episodeUrl || $0.episodeNumber == item.episodeNumber }),
           ep.isDownloaded {
            folder = ep.folder
        }
        if let folder = folder,
           let path = try? await api.downloadedStream(folder: folder, season: item.season, episode: item.episodeNumber),
           let shared = try? await api.share(path),
           let url = api.absolute(shared) {
            return url
        }
        let live = try await api.liveStream(item.episodeUrl, language: item.language, provider: item.provider)
        guard let url = api.absolute(live.url) else { throw ApiError(status: 0, message: "Ungültige Stream-Adresse") }
        return url
    }

    func toggle() async {
        if gcast.connected != nil { gcast.toggle() } else { await simple("toggle") }
    }

    func stop() async {
        if gcast.connected != nil { gcast.stop() } else { await simple("stop") }
    }

    func seek(by seconds: Int) async {
        if gcast.connected != nil {
            gcast.seek(by: seconds)
            return
        }
        guard let t = screenTarget else { return }
        try? await api.castCommand(t.id, ["type": "seek", "delta": seconds])
    }

    private func simple(_ type: String) async {
        guard let t = screenTarget else { return }
        try? await api.castCommand(t.id, ["type": type])
    }
}
