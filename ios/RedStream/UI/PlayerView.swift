import AVFoundation
import Combine
import SwiftUI

private let resumeMinSeconds = 30.0
private let completedRatio = 0.9

/// Playback logic of the phone player: resolves the stream (downloaded file
/// on the server, else the direct-stream relay), resumes, saves progress,
/// moves on to the next episode and switches language.
@MainActor
final class PlayerModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }

    let player = AVPlayer()
    private let app: AppState

    @Published private(set) var item: PlayItem
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var current: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var languages: [String] = []

    private var next: PlayItem?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var bag = Set<AnyCancellable>()
    private var itemBag = Set<AnyCancellable>()

    init(app: AppState, item: PlayItem) {
        self.app = app
        self.item = item
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.current = time.seconds.isFinite ? time.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self = self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.ended()
            }
            .store(in: &bag)
        // Progress every 10 s while playing.
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self = self else { return }
                if self.isPlaying { self.save() }
            }
        }
    }

    func start() { load(startAt: nil, allowDownloaded: true) }

    func close() {
        save()
        player.pause()
        loadTask?.cancel()
        saveTask?.cancel()
        if let o = timeObserver { player.removeTimeObserver(o) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    func retry() { load(startAt: current > 0 ? current : nil, allowDownloaded: true) }

    func togglePlay() { isPlaying ? player.pause() : player.play() }

    func seek(to seconds: Double) {
        let t = max(0, duration > 0 ? min(seconds, duration - 1) : seconds)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        current = t
    }

    func skip(_ delta: Double) { seek(to: current + delta) }

    func switchLanguage(_ lang: String) {
        guard lang != item.language else { return }
        save()
        let position = current
        // A file on disk might be in the old language.
        item.language = lang
        item.provider = nil
        item.folder = nil
        let seriesUrl = item.seriesUrl
        Task { try? await app.api.setSeriesLanguage(seriesUrl, lang) }
        load(startAt: position, allowDownloaded: false)
    }

    /// Hand over to the TV: save the position, the TV resumes from it.
    func handOff() {
        save()
        player.pause()
        let handoff = item
        let cast = app.cast
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // let the progress save land first
            try? await cast.play(handoff)
        }
    }

    func save(completed: Bool = false) {
        guard duration > 0 else { return }
        let pos = current
        let done = completed || pos / duration >= completedRatio
        let snapshot = item
        let dur = duration
        let api = app.api
        Task.detached { try? await api.saveProgress(snapshot, position: pos, duration: dur, completed: done) }
    }

    private func ended() {
        save(completed: true)
        if let n = next {
            item = n
            load(startAt: nil, allowDownloaded: true)
        }
    }

    private func load(startAt: Double?, allowDownloaded: Bool) {
        loadTask?.cancel()
        phase = .loading
        player.pause()
        current = startAt ?? 0
        duration = 0
        let target = item
        let api = app.api
        loadTask = Task {
            do {
                let (url, nextItem) = try await Self.resolve(api: api, item: target, allowDownloaded: allowDownloaded)
                guard !Task.isCancelled else { return }
                next = nextItem
                var resume = startAt
                if resume == nil, let p = try? await api.episodeProgress(target.episodeUrl) {
                    if !p.isCompleted, p.position > resumeMinSeconds, p.position < p.duration - 10 { resume = p.position }
                }
                guard !Task.isCancelled else { return }
                // Downloaded files sit behind the login; relay URLs don't need it but don't mind.
                let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": api.authHeaders()])
                let playerItem = AVPlayerItem(asset: asset)
                watch(playerItem)
                player.replaceCurrentItem(with: playerItem)
                if let r = resume {
                    _ = await player.seek(to: CMTime(seconds: r, preferredTimescale: 600))
                    current = r
                }
                player.play()
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
            if let langs = try? await api.providers(target.episodeUrl) {
                languages = sortLanguages(langs.keys)
            }
        }
    }

    private func watch(_ playerItem: AVPlayerItem) {
        itemBag.removeAll()
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak playerItem] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay: self.phase = .ready
                case .failed:
                    let reason = playerItem?.error?.localizedDescription ?? "unbekannter Fehler"
                    self.phase = .failed("Wiedergabe fehlgeschlagen: \(reason)")
                default: break
                }
            }
            .store(in: &itemBag)
    }

    /// Finds the episode on the server's disk and the episode after it.
    private static func lookupSeason(api: Api, item: PlayItem) async throws -> (Episode?, PlayItem?) {
        guard let season = try await api.seasons(item.seriesUrl).first(where: { $0.seasonNumber == item.season }) else {
            return (nil, nil)
        }
        let eps = try await api.episodes(season.url)
        guard let idx = eps.firstIndex(where: { $0.url == item.episodeUrl || $0.episodeNumber == item.episodeNumber }) else {
            return (nil, nil)
        }
        var next: PlayItem?
        if idx + 1 < eps.count {
            let n = eps[idx + 1]
            var copy = item
            copy.episodeUrl = n.url
            copy.episodeNumber = n.episodeNumber
            copy.episodeTitle = nonEmpty(n.title)
            copy.absoluteEpisodeNumber = n.absoluteEpisodeNumber
            copy.folder = n.isDownloaded ? n.folder : nil
            next = copy
        }
        return (eps[idx], next)
    }

    private static func resolve(api: Api, item: PlayItem, allowDownloaded: Bool) async throws -> (URL, PlayItem?) {
        let (ep, next) = (try? await lookupSeason(api: api, item: item)) ?? (nil, nil)
        let folder = allowDownloaded ? (item.folder ?? (ep?.isDownloaded == true ? ep?.folder : nil)) : nil
        if let folder = folder,
           let path = try? await api.downloadedStream(folder: folder, season: item.season, episode: item.episodeNumber) {
            // Login-free URL, so AirPlay to an Apple TV works (it fetches the
            // stream itself and can't send our auth header).
            let shared = try? await api.share(path)
            if let url = api.absolute(shared ?? path) { return (url, next) }
        }
        let live = try await api.liveStream(item.episodeUrl, language: item.language, provider: item.provider)
        guard let url = api.absolute(live.url) else { throw ApiError(status: 0, message: "Ungültige Stream-Adresse") }
        return (url, next)
    }
}

/// AVPlayerLayer as a SwiftUI view.
private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ uiView: LayerView, context: Context) {}
}

struct PlayerView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController
    @StateObject private var model: PlayerModel
    @State private var controlsVisible = true
    @State private var scrubbing: Double?
    @State private var hideTask: Task<Void, Never>?

    /// `app` is passed in because the model needs it before the environment exists.
    init(app: AppState, initial: PlayItem) {
        _model = StateObject(wrappedValue: PlayerModel(app: app, item: initial))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: model.player).ignoresSafeArea()

            Color.black.opacity(controlsVisible ? 0.35 : 0.001)
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            switch model.phase {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Stream wird vorbereitet…").foregroundColor(.white)
                }
            case let .failed(message):
                VStack(spacing: 12) {
                    Text(message).foregroundColor(RS.error).multilineTextAlignment(.center)
                    HStack {
                        Button("Erneut versuchen") { model.retry() }.buttonStyle(PrimaryButtonStyle())
                        Button("Schließen") { close() }.buttonStyle(OutlineButtonStyle())
                    }
                }
                .padding(24)
            case .ready:
                if controlsVisible { centerControls }
            }

            if controlsVisible || model.phase != .ready {
                VStack {
                    topBar
                    Spacer()
                    if model.phase == .ready { bottomBar }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            AppDelegate.lock(.landscape)
            UIApplication.shared.isIdleTimerDisabled = true
            model.start()
            scheduleHide()
        }
        .onDisappear {
            model.close()
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.lock(AppDelegate.defaultOrientations)
        }
        .onChange(of: model.isPlaying) { _ in scheduleHide() }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: close) {
                Image(systemName: "chevron.backward").font(.title2.weight(.semibold)).foregroundColor(.white).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zurück")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.item.seriesTitle).font(.headline).foregroundColor(.white).lineLimit(1)
                Text(epCode(model.item.season, model.item.episodeNumber) + (model.item.episodeTitle.map { " · " + $0 } ?? ""))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer()
            AirPlayButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            if !model.languages.isEmpty {
                Menu {
                    ForEach(model.languages, id: \.self) { lang in
                        Button {
                            model.switchLanguage(lang)
                        } label: {
                            if lang == model.item.language {
                                Label(languageLabel(lang), systemImage: "checkmark")
                            } else {
                                Text(languageLabel(lang))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "character.bubble").font(.title3).foregroundColor(.white).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Sprache")
            }
            Button {
                if cast.target == nil {
                    app.castSheetOpen = true
                } else {
                    model.handOff()
                    close()
                }
            } label: {
                Label(cast.target.map { "Auf \($0.name)" } ?? "Auf TV", systemImage: "tv")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(Color.white.opacity(0.5)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var centerControls: some View {
        HStack(spacing: 48) {
            Button { model.skip(-10); scheduleHide() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 34)).foregroundColor(.white)
            }
            .accessibilityLabel("10 Sek. zurück")
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.black)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.white))
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Abspielen")
            Button { model.skip(10); scheduleHide() } label: {
                Image(systemName: "goforward.10").font(.system(size: 34)).foregroundColor(.white)
            }
            .accessibilityLabel("10 Sek. vor")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubbing ?? model.current },
                    set: { scrubbing = $0 }
                ),
                in: 0...max(model.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let s = scrubbing {
                        model.seek(to: s)
                        scrubbing = nil
                        scheduleHide()
                    } else {
                        hideTask?.cancel()
                    }
                }
            )
            .tint(RS.accent)
            HStack {
                Text(formatTime(scrubbing ?? model.current)).foregroundColor(.white)
                Text("·").foregroundColor(.white.opacity(0.6))
                Text(formatTime(model.duration)).foregroundColor(.white.opacity(0.75))
                Spacer()
            }
            .font(.subheadline.monospacedDigit())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        scheduleHide()
    }

    /// Controls fade out after a few seconds of playback.
    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled, model.isPlaying, scrubbing == nil {
                withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
            }
        }
    }

    private func close() {
        app.playing = nil
    }
}
