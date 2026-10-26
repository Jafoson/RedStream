import SwiftUI

/// Tabs Start / Entdecken / Suche / Meine Liste / Mehr, each its own
/// navigation stack, plus the TV remote bar, the target picker and the
/// phone player on top.
struct MainView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            TabRoot(title: "Start") { HomeView() }
                .tabItem { Label("Start", systemImage: "house.fill") }
            TabRoot(title: "Entdecken") { BrowseView() }
                .tabItem { Label("Entdecken", systemImage: "safari.fill") }
            TabRoot(title: "Suche") { SearchView() }
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            TabRoot(title: "Meine Liste") { WatchlistView() }
                .tabItem { Label("Meine Liste", systemImage: "bookmark.fill") }
            TabRoot(title: "Mehr") { MoreView() }
                .tabItem { Label("Mehr", systemImage: "person.fill") }
        }
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 120) }
        .sheet(isPresented: $app.castSheetOpen) { CastSheet() }
        .fullScreenCover(item: $app.playing) { item in
            PlayerView(app: app, initial: item)
                .environmentObject(app)
                .environmentObject(app.cast)
        }
    }
}

/// One tab: navigation stack with the series page as destination and the
/// remote bar above the tab bar.
private struct TabRoot<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .screenChrome(title)
                .navigationDestination(for: SeriesRef.self) { ref in
                    DetailView(ref: ref).screenChrome("", large: false)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { RemoteBar() }
    }
}

extension View {
    /// Dark background, title and the "Auf TV abspielen" button.
    func screenChrome(_ title: String, large: Bool = true) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RS.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(large ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { CastButton() }
            }
    }
}

struct CastButton: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var cast: CastController

    var body: some View {
        Button {
            app.castSheetOpen = true
        } label: {
            Image(systemName: cast.target != nil ? "tv.inset.filled" : "tv")
                .foregroundColor(cast.target != nil ? RS.accent : RS.text)
        }
        .accessibilityLabel("Auf TV abspielen")
    }
}

struct ToastView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let text = app.toast {
            Text(text)
                .font(.subheadline)
                .foregroundColor(RS.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(RS.panel3))
                .padding(.horizontal, 16)
                .transition(.opacity)
        }
    }
}
