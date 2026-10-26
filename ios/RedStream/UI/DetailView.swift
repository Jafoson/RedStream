import SwiftUI

struct DetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController
    let ref: SeriesRef

    @State private var detail: SeriesDetail?
    @State private var seasons: Load<[Season]> = .loading
    @State private var seasonIndex: Int?
    @State private var episodes: Load<[Episode]> = .loading
    @State private var progress: [String: ProgressEntry] = [:]
    @State private var inList: Bool?
    @State private var language: String?
    @State private var descriptionExpanded = false

    private var title: String {
        if let t = detail?.title, !t.isEmpty { return t }
        return ref.title
    }

    private var season: Season? {
        guard let list = seasons.value, !list.isEmpty else { return nil }
        return list[min(max(seasonIndex ?? 0, 0), list.count - 1)]
    }

    private var episodeList: [Episode] { episodes.value ?? [] }

    /// "Weiterschauen": the furthest episode of this season that was started
    /// and not finished, else the one after the furthest finished one.
    private var nextUp: Episode? {
        guard let first = episodeList.first else { return nil }
        guard let furthest = episodeList.filter({ progress[$0.url] != nil }).max(by: { $0.episodeNumber < $1.episodeNumber }) else {
            return first
        }
        if progress[furthest.url]?.isCompleted != true { return furthest }
        return episodeList.first { $0.episodeNumber > furthest.episodeNumber } ?? furthest
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                actions
                if let desc = detail?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(RS.muted)
                        .lineLimit(descriptionExpanded ? nil : 3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .onTapGesture { descriptionExpanded.toggle() }
                }
                seasonTabs
                episodeSection
            }
            .padding(.bottom, 24)
        }
        .task(id: ref.url) { await loadSeries() }
        .task(id: "\(ref.url)|\(app.profileVersion)") { await pollProgress() }
        .task(id: season?.url) { await loadEpisodes() }
    }

    // MARK: Sections

    private var hero: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(RemoteImage(url: app.api.absolute(nonEmpty(detail?.backdropUrl) ?? detail?.posterUrl), placeholder: ""))
            .overlay(LinearGradient(colors: [.clear, RS.bg], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(RS.text)
                        .lineLimit(2)
                    let meta = [nonEmpty(detail?.releaseYear), nonEmpty(detail?.genres?.prefix(3).joined(separator: " · "))].compactMap { $0 }
                    if !meta.isEmpty { Muted(meta.joined(separator: "  ·  ")) }
                }
                .padding(16)
            }
            .clipped()
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let ep = nextUp { app.play(item(ep)) }
                } label: {
                    HStack {
                        Image(systemName: cast.target != nil ? "tv" : "play.fill")
                        Text(playLabel).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(nextUp == nil)
                .opacity(nextUp == nil ? 0.5 : 1)

                Button(action: toggleWatchlist) {
                    Image(systemName: inList == true ? "bookmark.fill" : "bookmark")
                        .font(.title2)
                        .foregroundColor(inList == true ? RS.accent : RS.text)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Meine Liste")
            }
            let available = sortLanguages(episodeList.flatMap { $0.availableLanguages ?? [] })
            if !available.isEmpty || language != nil {
                Menu {
                    let options = language.map { available.contains($0) ? available : available + [$0] } ?? available
                    ForEach(options, id: \.self) { lang in
                        Button {
                            setLanguage(lang)
                        } label: {
                            if lang == language {
                                Label(languageLabel(lang), systemImage: "checkmark")
                            } else {
                                Text(languageLabel(lang))
                            }
                        }
                    }
                } label: {
                    Label(language.map(languageLabel) ?? "Sprache", systemImage: "character.bubble")
                        .font(.body.weight(.medium))
                        .foregroundColor(RS.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(RS.muted2, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var playLabel: String {
        guard let ep = nextUp else { return "Abspielen" }
        let started = progress[ep.url] != nil
        return (started ? "Weiterschauen " : "Abspielen ") + epCode(season?.seasonNumber ?? 1, ep.episodeNumber)
    }

    @ViewBuilder
    private var seasonTabs: some View {
        switch seasons {
        case .loading:
            ProgressView().tint(RS.accent).frame(maxWidth: .infinity).padding(24)
        case let .failed(message):
            ErrorBox(message: message, retry: { Task { await loadSeries() } })
        case let .ok(list):
            if list.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(list.enumerated()), id: \.element.url) { i, se in
                            let selected = i == (seasonIndex ?? 0)
                            Button {
                                seasonIndex = i
                            } label: {
                                VStack(spacing: 6) {
                                    Text(se.areMovies == true ? "Filme" : "Staffel \(se.seasonNumber)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(selected ? RS.accent : RS.muted)
                                    Rectangle().fill(selected ? RS.accent : Color.clear).frame(height: 3)
                                }
                                .padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var episodeSection: some View {
        switch episodes {
        case .loading:
            if season != nil { ProgressView().tint(RS.accent).frame(maxWidth: .infinity).padding(24) }
        case let .failed(message):
            ErrorBox(message: message, retry: { Task { await loadEpisodes() } })
        case let .ok(list):
            LazyVStack(spacing: 0) {
                ForEach(list) { ep in
                    EpisodeRow(
                        episode: ep,
                        progress: progress[ep.url],
                        tvName: cast.target?.name,
                        onPlay: { app.play(item(ep)) },
                        onPlayPhone: { app.play(item(ep), forcePhone: true) }
                    )
                }
            }
        }
    }

    // MARK: Data

    private func item(_ ep: Episode) -> PlayItem {
        PlayItem(
            episodeUrl: ep.url,
            seriesTitle: title,
            seriesUrl: ref.url,
            season: season?.seasonNumber ?? 1,
            episodeNumber: ep.episodeNumber,
            episodeTitle: nonEmpty(ep.title),
            absoluteEpisodeNumber: ep.absoluteEpisodeNumber,
            language: language,
            folder: ep.isDownloaded ? ep.folder : nil
        )
    }

    private func loadSeries() async {
        seasons = .loading
        let api = app.api
        let url = ref.url
        async let d = try? api.series(url)
        async let l = try? api.preferredLanguage(url)
        async let w = try? api.inWatchlist(url)
        do {
            let list = try await api.seasons(url)
            seasons = .ok(list)
            if seasonIndex == nil {
                // Start on the season of the furthest-watched episode.
                let all = (try? await app.api.allProgress())?.filter { $0.seriesUrl == ref.url } ?? []
                let frontier = all.max { ($0.season ?? 0) * 10000 + ($0.episodeNumber ?? 0) < ($1.season ?? 0) * 10000 + ($1.episodeNumber ?? 0) }
                seasonIndex = list.firstIndex { $0.seasonNumber == frontier?.season } ?? 0
            }
        } catch {
            seasons = .failed(error.localizedDescription)
        }
        detail = await d
        language = await l
        inList = await w
    }

    private func loadEpisodes() async {
        guard let s = season else { return }
        episodes = .loading
        do {
            episodes = .ok(try await app.api.episodes(s.url))
        } catch {
            if !(error is CancellationError) { episodes = .failed(error.localizedDescription) }
        }
    }

    /// Polled like the web app's detail page, so progress stays current
    /// after coming back from the player or while a TV plays this series.
    private func pollProgress() async {
        while !Task.isCancelled {
            if let all = try? await app.api.allProgress() {
                var map: [String: ProgressEntry] = [:]
                for p in all where p.seriesUrl == ref.url { map[p.episodeUrl] = p }
                progress = map
            }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }
    }

    private func toggleWatchlist() {
        guard let now = inList else { return }
        Task {
            do {
                if now {
                    try await app.api.removeFromWatchlist(ref.url)
                } else {
                    try await app.api.addToWatchlist(ref.url, title: title, poster: detail?.posterUrl)
                }
                inList = !now
            } catch {
                app.showToast(error.localizedDescription)
            }
        }
    }

    private func setLanguage(_ lang: String) {
        language = lang
        Task { try? await app.api.setSeriesLanguage(ref.url, lang) }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let progress: ProgressEntry?
    let tvName: String?
    let onPlay: () -> Void
    let onPlayPhone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    Text("\(episode.episodeNumber)")
                        .font(.body.weight(.heavy))
                        .foregroundColor(RS.text)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(RS.panel2))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(episode.title.isEmpty ? "Folge \(episode.episodeNumber)" : episode.title)
                            .font(.body.weight(.semibold))
                            .foregroundColor(RS.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            if episode.isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(RS.muted)
                                    .accessibilityLabel("Heruntergeladen")
                            }
                            statusText
                        }
                        if let p = progress, !p.isCompleted, p.duration > 0 {
                            ProgressLine(fraction: p.fraction, height: 3)
                                .frame(width: 160)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let tvName = tvName {
                Menu {
                    Button { onPlay() } label: { Label("Auf \(tvName) abspielen", systemImage: "tv") }
                    Button { onPlayPhone() } label: { Label("Auf diesem iPhone abspielen", systemImage: "iphone") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(RS.text)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Optionen")
            } else {
                Image(systemName: "play.fill").foregroundColor(RS.accent).accessibilityLabel("Abspielen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        if let p = progress, p.isCompleted {
            Text("Gesehen").font(.caption).foregroundColor(RS.accent)
        } else if let p = progress, p.duration > 0 {
            Text("\(Int(p.fraction * 100)) % gesehen").font(.caption).foregroundColor(RS.muted)
        } else {
            Text(sortLanguages(episode.availableLanguages ?? []).map(shortLanguageLabel).joined(separator: " · "))
                .font(.caption)
                .foregroundColor(RS.muted2)
                .lineLimit(1)
        }
    }
}

func nonEmpty(_ s: String?) -> String? {
    guard let s = s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    return s
}
