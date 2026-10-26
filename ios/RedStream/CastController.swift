import Combine
import Foundation

/// "Auf TV abspielen": which TV is the playback target, and remote control
/// for it. Two kinds of TV:
/// - a RedStream screen: a browser running the web app (see web/cast.py),
///   controlled through the server; remembered across launches;
/// - a Google Cast device (Chromecast, Android TV), see `GoogleCastManager`.
/// No target = play on this phone (which may itself be AirPlaying to an Apple TV).
/// Like the TV/desktop player: jump to the next episode 30 s before the end
/// (its 40 s "Nächste Folge" window minus the 10 s countdown).
private let castAdvanceRemaining = 30.0

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
    // The device's queue by URL — the next episode is appended right away so
    // the TV moves on by itself; while the app runs it's topped up one at a time.
    private var gcastQueue: [String: PlayItem] = [:]
    private var nextQueuedFor = Set<String>()
    private var queuedNext: [String: PlayItem] = [:]
    private var advancedFrom = Set<String>()
    private var followTask: Task<Void, Never>?
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
        // Follow the device through its queue: a new item playing → that's the
        // current episode (the previous one counts as watched), top the queue
        // up, and skip ahead 30 s before the end like the desktop player.
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.followQueue()
            }
        }
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

    private func followQueue() {
        guard gcast.connected != nil else { return }
        if let id = gcast.contentID, let playing = gcastQueue[id], let cur = gcastItem, playing.episodeUrl != cur.episodeUrl {
            let dur = gcast.duration
            if dur > 0 { Task { try? await api.saveProgress(cur, position: dur, duration: dur, completed: true) } }
            gcastItem = playing
        }
        guard let now = gcastItem, gcast.playerState != "idle" else { return }
        if !nextQueuedFor.contains(now.episodeUrl) { Task { await queueNext(after: now) } }
        let remaining = gcast.duration - gcast.position
        if gcast.playerState == "playing", gcast.duration > 60, remaining <= castAdvanceRemaining,
           queuedNext[now.episodeUrl] != nil, advancedFrom.insert(now.episodeUrl).inserted {
            gcast.next()
        }
    }

    /// Puts the episode after `item` into the device's queue (once).
    private func queueNext(after item: PlayItem) async {
        guard nextQueuedFor.insert(item.episodeUrl).inserted else { return }
        do {
            guard let next = try await nextEpisode(after: item) else { return }
            let url = try await loginFreeURL(next)
            gcast.append(url: url, title: next.seriesTitle, subtitle: subtitle(next))
            gcastQueue[url.absoluteString] = next
            queuedNext[item.episodeUrl] = next
        } catch {
            nextQueuedFor.remove(item.episodeUrl) // try again next tick
        }
    }

    private func nextEpisode(after item: PlayItem) async throws -> PlayItem? {
        guard let season = try await api.seasons(item.seriesUrl).first(where: { $0.seasonNumber == item.season }) else { return nil }
        let eps = try await api.episodes(season.url)
        guard let idx = eps.firstIndex(where: { $0.url == item.episodeUrl || $0.episodeNumber == item.episodeNumber }),
              idx + 1 < eps.count else { return nil }
        let n = eps[idx + 1]
        var copy = item
        copy.episodeUrl = n.url
        copy.episodeNumber = n.episodeNumber
        copy.episodeTitle = nonEmpty(n.title)
        copy.absoluteEpisodeNumber = n.absoluteEpisodeNumber
        copy.folder = n.isDownloaded ? n.folder : nil
        return copy
    }

    private func subtitle(_ item: PlayItem) -> String {
        epCode(item.season, item.episodeNumber) + (item.episodeTitle.map { " · " + $0 } ?? "")
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
            gcastQueue = [url.absoluteString: item]
            nextQueuedFor = []
            queuedNext = [:]
            advancedFrom = []
            gcastItem = item
            gcast.load(url: url, title: item.seriesTitle, subtitle: subtitle(item), start: resume)
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
