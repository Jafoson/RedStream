import SwiftUI

// MARK: Async loading

enum Load<T> {
    case loading
    case ok(T)
    case failed(String)

    var value: T? {
        if case let .ok(v) = self { return v }
        return nil
    }
}

/// Shows a spinner / error with retry / the content of a `Load`.
struct LoadView<T, Content: View>: View {
    let state: Load<T>
    var retry: (() -> Void)?
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().tint(RS.accent).frame(maxWidth: .infinity).padding(32)
        case let .failed(message):
            ErrorBox(message: message, retry: retry)
        case let .ok(value):
            content(value)
        }
    }
}

struct ErrorBox: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(message).foregroundColor(RS.error).multilineTextAlignment(.center)
            if let retry = retry {
                Button("Erneut versuchen", action: retry).buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: Building blocks

struct SectionTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(RS.accent).frame(width: 4, height: 20)
            Text(text).font(.title3.weight(.heavy)).foregroundColor(RS.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(RS.accent.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(RS.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().stroke(RS.muted2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Remote image with a gradient + initial placeholder.
struct RemoteImage: View {
    let url: URL?
    var placeholder: String = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [RS.panel3, RS.panel], startPoint: .top, endPoint: .bottom)
            if !placeholder.isEmpty {
                Text(placeholder.prefix(1).uppercased())
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(RS.muted2)
            }
            if let url = url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .clipped()
    }
}

struct ProgressLine: View {
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.5))
                Rectangle().fill(RS.accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct PosterCard: View {
    let title: String
    let imageUrl: URL?
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(206.0 / 300.0, contentMode: .fit)
                .overlay(RemoteImage(url: imageUrl, placeholder: title))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(RS.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle = subtitle {
                Text(subtitle).font(.caption).foregroundColor(RS.muted).lineLimit(1)
            }
        }
    }
}

/// Grid of posters opening the series page.
struct PosterGrid: View {
    @EnvironmentObject var app: AppState
    let items: [BrowseItem]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.link) { item in
                NavigationLink(value: SeriesRef(url: item.link, title: item.name)) {
                    PosterCard(title: item.name, imageUrl: app.api.absolute(item.posterUrl))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

struct Rail: View {
    @EnvironmentObject var app: AppState
    let title: String
    let items: [BrowseItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items, id: \.link) { item in
                            NavigationLink(value: SeriesRef(url: item.link, title: item.name)) {
                                PosterCard(title: item.name, imageUrl: app.api.absolute(item.posterUrl))
                                    .frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

struct Muted: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline).foregroundColor(RS.muted)
    }
}

// MARK: Formatting

/// Site language keys -> what you hear/read (same wording as the web player).
func languageLabel(_ lang: String) -> String {
    switch lang {
    case "German Dub": return "Deutsch"
    case "English Dub": return "Englisch"
    case "German Sub": return "Japanisch · deutsche Untertitel"
    case "English Sub": return "Japanisch · englische Untertitel"
    default: return lang
    }
}

/// Compact form for episode rows, where both sub variants would otherwise read "Japanisch".
func shortLanguageLabel(_ lang: String) -> String {
    switch lang {
    case "German Sub": return "Untertitel DE"
    case "English Sub": return "Untertitel EN"
    default: return languageLabel(lang)
    }
}

private let languageOrder = ["German Dub", "German Sub", "English Sub", "English Dub"]

func sortLanguages<S: Sequence>(_ langs: S) -> [String] where S.Element == String {
    var seen = Set<String>()
    let unique = langs.filter { seen.insert($0).inserted }
    return unique.sorted { a, b in
        let ia = languageOrder.firstIndex(of: a) ?? 99
        let ib = languageOrder.firstIndex(of: b) ?? 99
        return ia == ib ? a < b : ia < ib
    }
}

func epCode(_ season: Int, _ episode: Int) -> String {
    String(format: "S%02dE%02d", season, episode)
}

func formatTime(_ seconds: Double?) -> String {
    let v = seconds ?? 0
    let s = v.isFinite ? max(Int(v), 0) : 0
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}
