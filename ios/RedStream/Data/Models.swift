import Foundation

// JSON models of the RedStream backend (same endpoints as the TV web app and
// the Android app). Decoded with `.convertFromSnakeCase`; almost everything is
// optional so a missing field never fails a whole screen.

/// Accepts true/false as well as SQLite's 0/1 (progress rows are raw DB rows).
struct FlexBool: Decodable, Hashable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            value = b
        } else if let n = try? c.decode(Double.self) {
            value = n != 0
        } else {
            value = false
        }
    }
}

// MARK: Device approval

struct AccessRequest: Decodable {
    let deviceId: String
    let status: String?
    let code: String?
}

struct AccessPoll: Decodable {
    let status: String
    let code: String?
    let token: String?
}

struct Profile: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let avatarColor: String?
}

struct ProfilesResponse: Decodable { let profiles: [Profile]? }

// MARK: Browse / search

struct BrowseItem: Decodable, Hashable {
    let title: String?
    let url: String?
    let posterUrl: String?

    var name: String { title ?? "" }
    var link: String { url ?? "" }
}

struct ResultsResponse: Decodable { let results: [BrowseItem]? }

struct PagedResponse: Decodable {
    let results: [BrowseItem]?
    let hasMore: Bool?
    let allGenres: [String]?
}

// MARK: Series detail

struct SeriesDetail: Decodable {
    let title: String?
    let posterUrl: String?
    let backdropUrl: String?
    let description: String?
    let genres: [String]?
    let releaseYear: String?
}

struct Season: Decodable, Hashable {
    let url: String
    let seasonNumber: Int
    let areMovies: Bool?
}

struct SeasonsResponse: Decodable { let seasons: [Season]? }

struct Episode: Decodable, Hashable, Identifiable {
    let url: String
    let episodeNumber: Int
    let titleDe: String?
    let titleEn: String?
    let downloaded: FlexBool?
    let availableLanguages: [String]?
    let folder: String?
    let absoluteEpisodeNumber: Int?

    var id: String { url }
    var isDownloaded: Bool { downloaded?.value ?? false }
    var title: String {
        if let t = titleDe, !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
        return titleEn ?? ""
    }
}

struct EpisodesResponse: Decodable { let episodes: [Episode]? }
struct LanguageResponse: Decodable { let language: String? }
struct ProvidersResponse: Decodable { let providers: [String: [String]]? }

// MARK: Progress / watchlist

struct ProgressEntry: Decodable, Hashable {
    let episodeUrl: String
    let seriesTitle: String?
    let seriesUrl: String?
    let season: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let positionSeconds: Double?
    let durationSeconds: Double?
    let completed: FlexBool?
    let posterUrl: String?
    let backdropUrl: String?
    let previewUrl: String?

    var isCompleted: Bool { completed?.value ?? false }
    var position: Double { positionSeconds ?? 0 }
    var duration: Double { durationSeconds ?? 0 }
    var fraction: Double {
        if isCompleted { return 1 }
        return duration > 0 ? min(max(position / duration, 0), 1) : 0
    }
}

struct ProgressListResponse: Decodable { let progress: [ProgressEntry]? }
struct ProgressOneResponse: Decodable { let progress: ProgressEntry? }

struct WatchlistItem: Decodable, Hashable {
    let title: String?
    let url: String?
    let posterUrl: String?
}

struct WatchlistResponse: Decodable { let items: [WatchlistItem]? }
struct InListResponse: Decodable { let inList: Bool? }

// MARK: Playback

struct StreamResponse: Decodable { let url: String }

struct LiveStream: Decodable {
    let url: String
    let kind: String?
    let provider: String?
}

// MARK: Cast

struct ScreenState: Decodable, Hashable {
    let status: String?
    let seriesTitle: String?
    let season: Int?
    let episodeNumber: Int?
    let position: Double?
    let duration: Double?
}

struct Screen: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let profileId: Int?
    let profileName: String?
    let state: ScreenState?
}

struct ScreensResponse: Decodable { let screens: [Screen]? }

// MARK: App-side

enum BrowseKind: String, CaseIterable, Identifiable {
    case series, anime, movies
    var id: String { rawValue }
    var label: String {
        switch self {
        case .series: return "Serien"
        case .anime: return "Anime"
        case .movies: return "Filme"
        }
    }
    var endpoint: String {
        switch self {
        case .series: return "/api/all-series"
        case .anime: return "/api/all-animes"
        case .movies: return "/api/all-movies"
        }
    }
}

/// A series page to open (navigation value).
struct SeriesRef: Hashable {
    let url: String
    let title: String
}

/// One episode to play — on the phone or on a TV.
struct PlayItem: Hashable, Identifiable {
    var episodeUrl: String
    var seriesTitle: String
    var seriesUrl: String
    var season: Int
    var episodeNumber: Int
    var episodeTitle: String? = nil
    var absoluteEpisodeNumber: Int? = nil
    var language: String? = nil
    var provider: String? = nil
    /// Set when the episode is on the server's disk (plays from there).
    var folder: String? = nil

    var id: String { episodeUrl }
}
