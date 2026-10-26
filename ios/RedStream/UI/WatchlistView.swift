import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var app: AppState
    @State private var list: Load<[WatchlistItem]> = .loading

    var body: some View {
        ScrollView {
            LoadView(state: list, retry: { Task { await load() } }) { items in
                if items.isEmpty {
                    Muted("Noch nichts auf deiner Liste. Auf der Seite einer Serie kannst du sie hinzufügen.")
                        .padding(16)
                } else {
                    PosterGrid(items: items.map { BrowseItem(title: $0.title, url: $0.url, posterUrl: $0.posterUrl) })
                }
            }
        }
        .refreshable { await load() }
        // Reloaded whenever the tab shows (a series may have been added meanwhile).
        .onAppear { Task { await load() } }
        .onChange(of: app.profileVersion) { _ in Task { await load() } }
    }

    private func load() async {
        do {
            list = .ok(try await app.api.watchlist())
        } catch {
            if list.value == nil { list = .failed(error.localizedDescription) }
        }
    }
}
