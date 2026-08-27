import { apiFetch } from './client'

export interface BrowseItem {
  title: string
  url: string
  poster_url?: string
  genres?: string[]
}

export function getNewAnimes(): Promise<BrowseItem[]> {
  return apiFetch<{ results: BrowseItem[] }>('/api/new-animes').then((r) => r.results)
}

export function getPopularAnimes(): Promise<BrowseItem[]> {
  return apiFetch<{ results: BrowseItem[] }>('/api/popular-animes').then((r) => r.results)
}

export function getNewSeries(): Promise<BrowseItem[]> {
  return apiFetch<{ results: BrowseItem[] }>('/api/new-series').then((r) => r.results)
}

export function getPopularSeries(): Promise<BrowseItem[]> {
  return apiFetch<{ results: BrowseItem[] }>('/api/popular-series').then((r) => r.results)
}

export function getPopularMovies(): Promise<BrowseItem[]> {
  return apiFetch<{ results: BrowseItem[] }>('/api/popular-movies').then((r) => r.results)
}

export interface PagedBrowseResult {
  results: BrowseItem[]
  total: number
  page: number
  per_page: number
  has_more: boolean
  all_genres: string[]
}

export type GridKind = 'series' | 'anime' | 'movies'

const GRID_ENDPOINT: Record<GridKind, string> = {
  series: '/api/all-series',
  anime: '/api/all-animes',
  movies: '/api/all-movies',
}

export function getAllByKind(kind: GridKind, page: number, genre?: string): Promise<PagedBrowseResult> {
  return apiFetch<PagedBrowseResult>(GRID_ENDPOINT[kind], {
    params: { page, per_page: 25, genre },
  })
}

export function getTmdbPoster(title: string): Promise<string> {
  return apiFetch<{ poster_url: string }>('/api/tmdb-poster', { params: { title } }).then((r) => r.poster_url)
}
