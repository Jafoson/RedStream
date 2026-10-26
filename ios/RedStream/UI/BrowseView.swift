import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var app: AppState
    @State private var kind: BrowseKind = .series
    @State private var genre: String?
    @State private var genres: [String] = []
    @State private var items: [BrowseItem] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Picker("Art", selection: $kind) {
                    ForEach(BrowseKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 4)

                if !genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(label: "Alle", selected: genre == nil) { genre = nil }
                            ForEach(genres, id: \.self) { g in
                                Chip(label: g, selected: genre == g) { genre = g }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items, id: \.link) { item in
                        NavigationLink(value: SeriesRef(url: item.link, title: item.name)) {
                            PosterCard(title: item.name, imageUrl: app.api.absolute(item.posterUrl))
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if item.link == items.last?.link { Task { await loadMore() } }
                        }
                    }
                }
                .padding(12)

                if let error = error {
                    ErrorBox(message: error, retry: { Task { await loadMore() } })
                } else if loading {
                    ProgressView().tint(RS.accent).padding(24)
                } else if items.isEmpty {
                    Muted("Nichts gefunden.").padding(24)
                }
            }
        }
        .task(id: "\(kind.rawValue)|\(genre ?? "")") { await reset() }
    }

    private func reset() async {
        items = []
        page = 1
        hasMore = true
        error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        let requested = (kind, genre, page)
        do {
            let r = try await app.api.allByKind(requested.0, page: requested.2, genre: requested.1)
            // Kind/genre changed meanwhile: a newer load owns the list.
            guard requested.0 == kind, requested.1 == genre else { return }
            let known = Set(items.map(\.link))
            items += (r.results ?? []).filter { !known.contains($0.link) }
            hasMore = r.hasMore ?? false
            page += 1
            if let g = r.allGenres, !g.isEmpty { genres = g }
            error = nil
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }
}

struct Chip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(selected ? RS.text : RS.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? RS.panel3 : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.clear : RS.muted2))
                )
        }
        .buttonStyle(.plain)
    }
}
