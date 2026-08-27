import { apiFetch } from './client'
import type { NextEpisodeRef } from '../navigation/playerState'

export interface SeriesDetail {
  title: string
  poster_url: string
  backdrop_url: string
  description: string
  genres: string[]
  release_year: string
}

export function getSeriesDetail(url: string): Promise<SeriesDetail> {
  return apiFetch<SeriesDetail>('/api/series', { params: { url } })
}

export interface Season {
  url: string
  season_number: number
  episode_count: number
  are_movies: boolean
}

export function getSeasons(seriesUrl: string): Promise<Season[]> {
  return apiFetch<{ seasons: Season[] }>('/api/seasons', { params: { url: seriesUrl } }).then((r) => r.seasons)
}

export interface Episode {
  url: string
  episode_number: number
  title_de: string
  title_en: string
  downloaded: boolean
  available_languages: string[]
  folder: string | null
  // Position across the whole series regardless of the site's season
  // splits — for shows like One Piece, where "season" boundaries are the
  // site's own batching rather than real broadcast seasons, "Staffel 12
  // Episode 2" alone doesn't convey that it's actually the ~409th episode
  // overall. `null` when the backend couldn't build the cumulative count
  // (e.g. a season with an unknown episode_count).
  absolute_episode_number: number | null
}

export function getEpisodes(seasonUrl: string): Promise<Episode[]> {
  return apiFetch<{ episodes: Episode[] }>('/api/episodes', { params: { url: seasonUrl } }).then((r) => r.episodes)
}

export function getProviders(episodeUrl: string): Promise<Record<string, string[]>> {
  return apiFetch<{ providers: Record<string, string[]> }>('/api/providers', { params: { url: episodeUrl } }).then(
    (r) => r.providers,
  )
}

export function getPreferredLanguage(seriesUrl?: string): Promise<string> {
  return apiFetch<{ language: string }>('/api/preferred-language', { params: { series_url: seriesUrl } }).then(
    (r) => r.language,
  )
}

export function getSeriesLanguage(seriesUrl: string): Promise<string | null> {
  return apiFetch<{ language: string | null }>('/api/series-language', { params: { url: seriesUrl } }).then(
    (r) => r.language,
  )
}

export function setSeriesLanguage(seriesUrl: string, language: string): Promise<void> {
  return apiFetch<void>('/api/series-language', { method: 'PUT', body: { url: seriesUrl, language } })
}

export function clearSeriesLanguage(seriesUrl: string): Promise<void> {
  return apiFetch<void>('/api/series-language', { method: 'DELETE', params: { url: seriesUrl } })
}

// Same-season-only (matches Flutter's own _playFromResume — no rollover into
// the next season's first episode). Used anywhere a "what comes after this
// episode" reference is needed without already having that season's episode
// list loaded in scope — resolves it fresh via one extra season+episode
// fetch. Returns null (not throwing) on any failure, since callers treat "no
// next episode known" as a normal, gracefully-degraded outcome, not an error.
export async function findNextEpisodeAfter(
  seriesUrl: string,
  season: number,
  episodeNumber: number,
): Promise<NextEpisodeRef | null> {
  try {
    const seasons = await getSeasons(seriesUrl)
    const seasonObj = seasons.find((s) => s.season_number === season)
    if (!seasonObj) return null
    const episodes = await getEpisodes(seasonObj.url)
    const idx = episodes.findIndex((e) => e.episode_number === episodeNumber)
    const next = idx >= 0 ? episodes[idx + 1] : undefined
    if (!next) return null
    return {
      episodeUrl: next.url,
      season,
      episodeNumber: next.episode_number,
      episodeTitle: next.title_de || next.title_en,
      absoluteEpisodeNumber: next.absolute_episode_number,
    }
  } catch {
    return null
  }
}
