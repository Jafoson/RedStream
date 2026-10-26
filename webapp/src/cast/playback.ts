// What this browser is playing right now, for the cast heartbeat (so the
// Android app can show it) and for executing remote commands on the
// <video> element. PlayerPage/DownloadPlayPage publish into it.

export interface NowPlaying {
  episodeUrl: string
  seriesTitle: string
  seriesUrl: string
  season: number
  episodeNumber: number
  episodeTitle?: string
  language?: string
}

let current: { info: NowPlaying; video: HTMLVideoElement | null } | null = null

/** `video` null = still resolving/downloading (status "loading"). */
export function setNowPlaying(info: NowPlaying, video: HTMLVideoElement | null): void {
  current = { info, video }
}

export function clearNowPlaying(info?: NowPlaying): void {
  // Only clear if nobody else took over in the meantime (a page that
  // unmounts after the next one already published its own state).
  if (!info || current?.info.episodeUrl === info.episodeUrl) current = null
}

export function getVideo(): HTMLVideoElement | null {
  return current?.video ?? null
}

export interface PlaybackState {
  status: 'idle' | 'loading' | 'playing' | 'paused' | 'buffering'
  episode_url?: string
  series_title?: string
  series_url?: string
  season?: number
  episode_number?: number
  episode_title?: string
  language?: string
  position?: number
  duration?: number
}

export function getPlaybackState(): PlaybackState {
  if (!current) return { status: 'idle' }
  const { info, video } = current
  const base = {
    episode_url: info.episodeUrl,
    series_title: info.seriesTitle,
    series_url: info.seriesUrl,
    season: info.season,
    episode_number: info.episodeNumber,
    episode_title: info.episodeTitle,
    language: info.language,
  }
  if (!video || !video.duration) return { status: 'loading', ...base }
  const buffering = !video.paused && video.readyState < 3
  return {
    status: video.paused ? 'paused' : buffering ? 'buffering' : 'playing',
    ...base,
    position: Math.round(video.currentTime),
    duration: Math.round(video.duration),
  }
}
