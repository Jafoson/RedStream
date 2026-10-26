import SwiftUI

private let rails = [
    ("Neue Anime", "/api/new-animes"),
    ("Beliebte Anime", "/api/popular-animes"),
    ("Neue Serien", "/api/new-series"),
    ("Beliebte Serien", "/api/popular-series"),
    ("Beliebte Filme", "/api/popular-movies"),
]

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var continueList: [ProgressEntry] = []
    @State private var railItems: [String: [BrowseItem]] = [:]
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !continueList.isEmpty {
                    SectionTitle(text: "Weiterschauen")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(continueList, id: \.episodeUrl) { p in
                                Button { app.play(item(for: p)) } label: { ContinueCard(entry: p) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 12)
                }
                ForEach(rails, id: \.1) { title, path in
                    Rail(title: title, items: railItems[path] ?? [])
                }
                if failed && railItems.isEmpty {
                    ErrorBox(message: "Server nicht erreichbar.", retry: { Task { await load() } })
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await load() }
        .task(id: app.profileVersion) { await load() }
        .onChange(of: app.playing) { playing in
            // Back from the player: progress moved on.
            if playing == nil { Task { continueList = (try? await app.api.continueWatching()) ?? continueList } }
        }
    }

    private func item(for p: ProgressEntry) -> PlayItem {
        PlayItem(
            episodeUrl: p.episodeUrl,
            seriesTitle: p.seriesTitle ?? "",
            seriesUrl: p.seriesUrl ?? "",
            season: p.season ?? 1,
            episodeNumber: p.episodeNumber ?? 1,
            episodeTitle: p.episodeTitle
        )
    }

    private func load() async {
        failed = false
        let api = app.api
        async let cont = try? api.continueWatching()
        await withTaskGroup(of: (String, [BrowseItem]?).self) { group in
            for (_, path) in rails {
                group.addTask { (path, try? await api.rail(path)) }
            }
            for await (path, items) in group {
                if let items = items { railItems[path] = items } else { failed = true }
            }
        }
        continueList = await cont ?? []
    }
}

private struct ContinueCard: View {
    @EnvironmentObject var app: AppState
    let entry: ProgressEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(RemoteImage(url: app.api.absolute(image), placeholder: ""))
                .overlay(alignment: .bottom) { ProgressLine(fraction: entry.fraction) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(entry.seriesTitle ?? "").font(.subheadline.weight(.semibold)).foregroundColor(RS.text).lineLimit(1)
            Text(epCode(entry.season ?? 1, entry.episodeNumber ?? 1) + (entry.episodeTitle.map { " · " + $0 } ?? ""))
                .font(.caption)
                .foregroundColor(RS.muted)
                .lineLimit(1)
        }
        .frame(width: 230)
    }

    private var image: String? {
        for candidate in [entry.previewUrl, entry.backdropUrl, entry.posterUrl] {
            if let c = candidate, !c.isEmpty { return c }
        }
        return nil
    }
}
