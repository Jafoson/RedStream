// Shared shape for react-router `location.state` passed into DownloadPlayPage
// and PlayerPage. Both are transient, click-through screens (matching
// Flutter's DownloadPlayScreen/PlayerScreen) — they are never meant to be
// bookmarked, so the identifying params beyond folder/season/episode travel
// via navigation state rather than the URL.
export interface NextEpisodeRef {
  episodeUrl: string
  season: number
  episodeNumber: number
  episodeTitle?: string
  // See DownloadPlayState.absoluteEpisodeNumber below.
  absoluteEpisodeNumber?: number | null
}

export interface DownloadPlayState {
  episodeUrl: string
  seriesTitle: string
  seriesUrl: string
  season: number
  episodeNumber: number
  episodeTitle?: string
  // Position across the whole series, not just within the site's own season
  // split — e.g. One Piece's "Staffel 12 Episode 2" is the ~409th episode
  // overall. Only ever known synchronously (from an already-loaded episode
  // list, e.g. DetailPage's) — unlike language/nextEpisode below, nothing
  // resolves this lazily on arrival if it's missing, so it's left `null`/
  // absent rather than costing another network round-trip; PlayerPage's
  // subtitle simply omits the absolute number in that case.
  absoluteEpisodeNumber?: number | null
  // Both optional: a caller that already knows them synchronously (e.g.
  // DetailPage's already-loaded language, or the next episode continuing in
  // the same language you're already watching in) can pass them through
  // directly. A caller that would otherwise need to await a network call
  // before navigating (Home's continue-watching cards, resolving the
  // episode *after* the one about to play) omits them instead and
  // navigates immediately — DownloadPlayPage resolves whichever is missing
  // itself, using the "Wird aufgelöst…" state it already shows on arrival,
  // so the click feels instant instead of the trigger sitting unresponsive.
  language?: string
  provider: string
  customPathId?: number | null
  nextEpisode?: NextEpisodeRef | null
}

export interface PlayerState {
  folder: string
  season: number
  episodeNumber: number
  episodeUrl: string
  seriesTitle: string
  seriesUrl: string
  episodeTitle?: string
  absoluteEpisodeNumber?: number | null
  language: string
  provider: string
  customPathId?: number | null
  nextEpisode?: NextEpisodeRef | null
  // Set when DownloadPlayPage already resolved+verified the .m3u8 URL while
  // confirming the episode is downloaded (it has to fetch this anyway just
  // to check the file really exists) — PlayerPage reuses it instead of
  // fetching the identical URL again a moment later, cutting a real
  // backend round-trip out of the already-downloaded fast path. Absent for
  // entry points that never resolved it (shouldn't normally happen once the
  // library fast path is taken, but PlayerPage falls back to fetching it
  // itself if missing).
  streamUrl?: string
}
