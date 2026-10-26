/** One episode to play — on the phone or on a TV (same shape as the native apps' PlayItem). */
export interface PlayItem {
  episodeUrl: string
  seriesTitle: string
  seriesUrl: string
  season: number
  episodeNumber: number
  episodeTitle?: string
  absoluteEpisodeNumber?: number | null
  language?: string
  provider?: string
  /** Set when the episode is on the server's disk (plays from there). */
  folder?: string | null
}

export interface CastScreenState {
  status?: 'idle' | 'loading' | 'playing' | 'paused' | 'buffering'
  series_title?: string
  season?: number
  episode_number?: number
  position?: number
  duration?: number
}

export interface CastScreen {
  id: string
  name: string
  profile_id: number | null
  profile_name: string | null
  online: boolean
  state: CastScreenState
}
