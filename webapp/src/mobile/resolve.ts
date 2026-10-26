// Where an episode plays from: the server's disk if it's downloaded, else
// the direct-stream relay. Shared by the phone player, Google Cast and
// AirPlay.
import { resolveLiveStream } from '../api/live'
import { getEpisodes, getSeasons } from '../api/series'
import { getStreamUrl, shareStreamUrl } from '../api/stream'
import type { PlayItem } from './types'

export interface ResolvedStream {
  url: string
  kind: 'hls' | 'file'
  /** The episode after this one in the same season, if any. */
  next: PlayItem | null
}

/** Finds the episode on the server's disk and the episode after it. */
async function lookupSeason(item: PlayItem) {
  const season = (await getSeasons(item.seriesUrl)).find((s) => s.season_number === item.season)
  if (!season) return { ep: null, next: null }
  const eps = await getEpisodes(season.url)
  const idx = eps.findIndex((e) => e.url === item.episodeUrl || e.episode_number === item.episodeNumber)
  if (idx < 0) return { ep: null, next: null }
  const n = eps[idx + 1]
  const next: PlayItem | null = n
    ? {
        ...item,
        episodeUrl: n.url,
        episodeNumber: n.episode_number,
        episodeTitle: (n.title_de || n.title_en || '').trim() || undefined,
        absoluteEpisodeNumber: n.absolute_episode_number,
        folder: n.downloaded ? n.folder : null,
      }
    : null
  return { ep: eps[idx], next }
}

/**
 * `loginFree`: the URL must work without the Authorization header (a TV
 * fetching it, or Safari's native HLS) — downloaded episodes then get a
 * short-lived /api/share URL; relay URLs are login-free anyway.
 */
export async function resolveStream(
  item: PlayItem,
  opts: { allowDownloaded?: boolean; loginFree?: boolean } = {},
): Promise<ResolvedStream> {
  const { allowDownloaded = true, loginFree = false } = opts
  const { ep, next } = await lookupSeason(item).catch(() => ({ ep: null, next: null }))
  const folder = allowDownloaded ? item.folder || (ep?.downloaded ? ep.folder : null) : null
  if (folder) {
    try {
      const path = await getStreamUrl({ folder, season: item.season, episode: item.episodeNumber })
      return { url: loginFree ? await shareStreamUrl(path) : path, kind: 'hls', next }
    } catch {
      // not on disk after all — stream it
    }
  }
  const live = await resolveLiveStream({ episodeUrl: item.episodeUrl, language: item.language, provider: item.provider })
  return { url: live.url, kind: live.kind, next }
}

export function absoluteUrl(path: string): string {
  return new URL(path, window.location.origin).href
}
