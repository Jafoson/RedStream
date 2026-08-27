import { useEffect, useState } from 'react'
import { MOBILE_S_MAX, MOBILE_L_MAX, TABLET_MAX, LAPTOP_MAX } from '../styles/breakpoints'
import { useIsTv } from './useIsTv'

function computeColumns(): number {
  const w = window.innerWidth
  if (w <= MOBILE_S_MAX) return 2
  if (w <= MOBILE_L_MAX) return 3
  if (w <= TABLET_MAX) return 4
  if (w <= LAPTOP_MAX) return 5
  return 6
}

// Single source of truth for "how many columns is the poster grid showing
// right now" — used identically by JS row-chunking (for the D-pad
// focus-engine's row/col shape, via tv/gridColumns.ts's chunk()) and by CSS
// (via a `--grid-cols` custom property set on the grid container). Because
// both consumers read the exact same number from here, there's no second
// value to keep in sync by convention — the JS/CSS desync failure mode this
// exists to prevent can't happen by construction.
//
// Listens on `matchMedia` for each tier boundary rather than a raw resize
// listener — fires only when a tier is actually crossed, not on every pixel
// of a window drag.
export function useGridColumns(): number {
  const isTv = useIsTv()
  const [cols, setCols] = useState(computeColumns)

  useEffect(() => {
    const queries = [
      window.matchMedia(`(max-width: ${MOBILE_S_MAX}px)`),
      window.matchMedia(`(max-width: ${MOBILE_L_MAX}px)`),
      window.matchMedia(`(max-width: ${TABLET_MAX}px)`),
      window.matchMedia(`(max-width: ${LAPTOP_MAX}px)`),
    ]
    const update = () => setCols(computeColumns())
    queries.forEach((q) => q.addEventListener('change', update))
    update()
    return () => queries.forEach((q) => q.removeEventListener('change', update))
  }, [])

  // A genuine TV is still a wide (≥1440px) display, which would otherwise
  // land on the same dense 6-column grid as a desktop monitor — Netflix's
  // own TV app uses fewer, larger tiles for 10-foot viewing, so TV mode caps
  // the column count regardless of raw viewport width.
  return isTv ? Math.min(cols, 5) : cols
}
