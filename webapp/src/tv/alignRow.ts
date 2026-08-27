import { useEffect } from 'react'
import { useFocusEngine } from './FocusEngine'

// Ported from the Claude Design project's screens.jsx alignRow — scrolls the
// page's .scroller container so the focused row (marked with data-row) sits
// near the top, accounting for the TV stage's uniform scale transform.
export function alignRow(scroller: HTMLElement | null, row: number) {
  if (!scroller) return
  if (row <= 0) {
    scroller.scrollTop = 0
    return
  }
  const el = scroller.querySelector<HTMLElement>(`[data-row="${row}"]`)
  if (!el) return
  const sRect = scroller.getBoundingClientRect()
  const eRect = el.getBoundingClientRect()
  const scale = sRect.width / scroller.clientWidth || 1
  const delta = (eRect.top - sRect.top) / scale - 120
  scroller.scrollTop += delta
}

/** Auto-scrolls a page's .scroller to the focused row — but ONLY when focus
 * moved there via keyboard/D-pad. A mouse hover also updates `focus` (so
 * `.is-foc` highlighting and Enter-key semantics stay correct), but must
 * never yank the page's scroll position around just because the pointer
 * passed over a card — that's the "scrolls on hover" bug this guards against. */
export function useAutoScrollRow(scrollerRef: React.RefObject<HTMLElement | null>) {
  const { focus } = useFocusEngine()
  useEffect(() => {
    if (focus.origin !== 'keyboard') return
    alignRow(scrollerRef.current, focus.region === 'content' ? focus.row : 0)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focus])
}
