import { useCallback, useState } from 'react'

// Independent implementation of the /react dashboard's expand/collapse
// pattern (not shared code, per project convention) — session-only here
// (no persistence needed for this app's simpler single-level library tree).
export function useExpandedSet(initial: string[] = []) {
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set(initial))

  const toggle = useCallback((key: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }, [])

  const isExpanded = useCallback((key: string) => expanded.has(key), [expanded])

  return { isExpanded, toggle }
}
