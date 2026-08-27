import { useEffect, useState } from 'react'

// Tries a prioritized list of candidate image URLs in order — used wherever
// a component wants "the real thing, else a more-specific fallback (e.g. the
// series' own backdrop), else nothing (caller renders its own generic
// placeholder)" instead of a single primary/placeholder pair. Advances past
// a URL once its <img> reports onError (a load failure, not just a missing
// value — falsy candidates are filtered out up front so they never even
// attempt to load); resets back to the front of the list whenever the
// candidate set itself changes (a different item's data, not just a
// re-render with the same URLs).
export function useFallbackImage(urls: (string | null | undefined)[]): {
  src: string | null
  onError: () => void
} {
  const candidates = urls.filter((u): u is string => !!u)
  const key = candidates.join('|')
  const [index, setIndex] = useState(0)
  useEffect(() => setIndex(0), [key])

  return {
    src: candidates[index] ?? null,
    onError: () => setIndex((i) => i + 1),
  }
}
