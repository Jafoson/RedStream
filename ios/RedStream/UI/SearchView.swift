import SwiftUI

private let sites = [("aniworld", "Anime"), ("sto", "Serien"), ("megakino", "Filme")]

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var text = ""
    @State private var query = ""
    @State private var site = "aniworld"
    @State private var results: Load<[BrowseItem]> = .ok([])
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(RS.muted)
                    TextField("", text: $text, prompt: Text("Titel suchen…").foregroundColor(RS.muted2))
                        .foregroundColor(RS.text)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { query = text.trimmingCharacters(in: .whitespaces) }
                        .accessibilityIdentifier("searchField")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).stroke(RS.muted2))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                HStack(spacing: 8) {
                    ForEach(sites, id: \.0) { key, label in
                        Chip(label: label, selected: site == key) {
                            site = key
                            query = text.trimmingCharacters(in: .whitespaces)
                            focused = false
                        }
                    }
                }
                .padding(.horizontal, 12)

                LoadView(state: results, retry: { Task { await search() } }) { list in
                    if !query.isEmpty && list.isEmpty {
                        Muted("Keine Treffer für „\(query)“.").padding(16)
                    }
                    PosterGrid(items: list)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .task(id: "\(site)|\(query)") { await search() }
    }

    private func search() async {
        guard !query.isEmpty else {
            results = .ok([])
            return
        }
        results = .loading
        do {
            results = .ok(try await app.api.search(query, site: site))
        } catch {
            if !(error is CancellationError) { results = .failed(error.localizedDescription) }
        }
    }
}
