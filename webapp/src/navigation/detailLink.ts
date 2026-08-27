// Shared helper for navigating to DetailPage from any poster/rail card —
// series URLs are full external URLs (aniworld.to/s.to/megakino), not clean
// path segments, so they travel as a query param rather than a route param.
import type { NavigateFunction } from 'react-router-dom'

export function detailPath(seriesUrl: string): string {
  return `/detail?url=${encodeURIComponent(seriesUrl)}`
}

export function goToDetail(navigate: NavigateFunction, seriesUrl: string, title?: string, posterUrl?: string) {
  navigate(detailPath(seriesUrl), { state: { title, posterUrl } })
}
