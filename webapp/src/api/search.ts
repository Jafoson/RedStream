import { apiFetch } from './client'

export type SearchSite = 'aniworld' | 'sto' | 'megakino'

export interface SearchResult {
  title: string
  url: string
  poster_url?: string
}

export function search(keyword: string, site: SearchSite): Promise<SearchResult[]> {
  return apiFetch<{ results: SearchResult[] }>('/api/search', {
    method: 'POST',
    body: { keyword, site },
    skipProfile: true,
  }).then((r) => r.results)
}
