import { apiFetch } from './client'

export interface WatchlistItem {
  title: string
  url: string
  poster_url?: string
}

export interface WatchlistEnrichedItem extends WatchlistItem {
  last_watched_at: string | null
  new_content: boolean
}

export function getWatchlist(): Promise<WatchlistItem[]> {
  return apiFetch<{ items: WatchlistItem[] }>('/api/watchlist').then((r) => r.items)
}

export function getWatchlistEnriched(): Promise<WatchlistEnrichedItem[]> {
  return apiFetch<{ items: WatchlistEnrichedItem[] }>('/api/watchlist/enriched').then((r) => r.items)
}

export function isInWatchlist(seriesUrl: string): Promise<boolean> {
  return apiFetch<{ in_list: boolean }>('/api/watchlist/check', { params: { url: seriesUrl } }).then(
    (r) => r.in_list,
  )
}

export function addToWatchlist(seriesUrl: string, seriesTitle: string, posterUrl?: string): Promise<void> {
  return apiFetch<void>('/api/watchlist', {
    method: 'POST',
    body: { series_url: seriesUrl, series_title: seriesTitle, poster_url: posterUrl },
  })
}

export function removeFromWatchlist(seriesUrl: string): Promise<void> {
  return apiFetch<void>('/api/watchlist', { method: 'DELETE', body: { series_url: seriesUrl } })
}
