import { apiFetch, apiUrl } from './client'

export interface StreamResult {
  url: string
}

export interface GetStreamParams {
  folder: string
  season: number
  episode: number
  customPathId?: number | null
}

/** Resolves the .m3u8 URL and normalizes it to a path-only URL (works both
 * dev-proxied and same-origin prod) — same pattern as react/src/api/stream.ts. */
export async function getStreamUrl(params: GetStreamParams): Promise<string> {
  const result = await apiFetch<StreamResult>('/api/stream', {
    params: {
      folder: params.folder,
      season: params.season,
      episode: params.episode,
      custom_path_id: params.customPathId ?? undefined,
    },
  })
  const parsed = new URL(result.url, window.location.origin)
  return parsed.pathname + parsed.search
}

/** The relative filepath backend endpoints (thumbnails, progress) expect —
 * derived the same way api.py's save-progress handler does, from the
 * /api/stream/files/<path> prefix of the resolved stream URL. */
export function streamFileFromUrl(streamUrl: string): string | null {
  const prefix = '/api/stream/files/'
  const idx = streamUrl.indexOf(prefix)
  if (idx === -1) return null
  return decodeURIComponent(streamUrl.slice(idx + prefix.length))
}

export interface ThumbnailMeta {
  status: 'ready' | 'generating'
  interval?: number
  total?: number
  cols?: number
  rows?: number
  thumb_w?: number
  thumb_h?: number
  sprite_filepath?: string
}

export function getThumbnails(filepath: string): Promise<ThumbnailMeta> {
  return apiFetch<ThumbnailMeta>('/api/thumbnails', { params: { filepath } })
}

export function thumbnailSpriteUrl(spriteFilepath: string): string {
  return apiUrl(`/api/thumbnails/sprite/${spriteFilepath}`)
}

export interface SkipInterval {
  start: number
  end: number
}

export interface SkipTimes {
  op: SkipInterval | null
  ed: SkipInterval | null
}

export function getSkipTimes(seriesTitle: string, episode: number): Promise<SkipTimes> {
  return apiFetch<SkipTimes>('/api/skip-times', { params: { series_title: seriesTitle, episode } })
}

export interface SaveProgressInput {
  episode_url: string
  series_title?: string
  series_url?: string
  season: number
  episode_number: number
  episode_title?: string
  position_seconds: number
  duration_seconds: number
  completed?: boolean
  stream_file?: string | null
  // Overrides the backend's normal "started = position_seconds > 30"
  // inference — needed when writing a synthetic position-0 row that must
  // still count as the continue-watching frontier (get_continue_watching
  // filters on started=1). Omit for real playback saves.
  started?: boolean
}

export function saveProgress(input: SaveProgressInput): Promise<void> {
  return apiFetch<void>('/api/progress', { method: 'POST', body: input })
}

export interface ProgressEntry {
  episode_url: string
  series_title: string
  series_url: string
  season: number
  episode_number: number
  episode_title: string
  position_seconds: number
  duration_seconds: number
  completed: boolean
  poster_url?: string
  // Horizontal/landscape TMDB backdrop for the series — used as a fallback
  // when preview_url is empty (episode never played, so its own preview
  // frame hasn't been generated yet — see thumbnails.py).
  backdrop_url?: string
  preview_url?: string
}

export function getAllProgress(opts: { continueOnly?: boolean; limit?: number } = {}): Promise<ProgressEntry[]> {
  return apiFetch<{ progress: ProgressEntry[] }>('/api/progress', {
    params: { continue: opts.continueOnly ? 1 : 0, limit: opts.limit },
  }).then((r) => r.progress)
}

export function getEpisodeProgress(episodeUrl: string): Promise<ProgressEntry | null> {
  return apiFetch<{ progress: ProgressEntry | null }>(`/api/progress/${encodeURIComponent(episodeUrl)}`).then(
    (r) => r.progress,
  )
}
