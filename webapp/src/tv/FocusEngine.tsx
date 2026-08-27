// Port of the Claude Design "RedStream TV" app.jsx focus state machine —
// {region, row, col} driven by arrow keys/Enter/Escape AND mouse hover/click
// (registerNav's activate callback is invoked by either input). Content
// screens register their focusable grid shape (row lengths) + an activate
// callback on mount; the sidebar is registered once by Shell.
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'

// Squared-distance threshold (px²) below which a hover's cursor position is
// treated as "the same place" as the last one — see setFocus below. 4px²
// (~2px of real movement) comfortably covers hand-tremor jitter while still
// being far smaller than any distance a deliberate move-to-a-different-card
// hover travels.
const MOUSE_JITTER_THRESHOLD_SQ = 4

// Some embedded TV browsers (e.g. Vewd/Opera TV Store — see its own
// developer docs, which recommend checking `event.key == 'Up'`) still
// report D-pad arrow presses using the older, pre-UI-Events-Level-3 `key`
// values instead of the standard 'ArrowUp'/'ArrowDown'/'ArrowLeft'/
// 'ArrowRight' every other target here uses; a remote-synthesized event (no
// real physical keyboard behind a TV remote's D-pad) may also skip `e.code`
// entirely, so this also falls back to the classic VK_LEFT/UP/RIGHT/DOWN
// `e.keyCode` values (37/38/39/40), unchanged since Netscape 4 and the most
// universally consistent of the three. Normalized once at the top of the
// keydown handler so the rest of this file only ever deals with the modern
// names — same defensive pattern as PlayerControls.tsx's normalizeKey.
function normalizeArrowKey(e: KeyboardEvent): string {
  const key = e.key
  if (key === 'Up' || e.keyCode === 38) return 'ArrowUp'
  if (key === 'Down' || e.keyCode === 40) return 'ArrowDown'
  if (key === 'Left' || e.keyCode === 37) return 'ArrowLeft'
  if (key === 'Right' || e.keyCode === 39) return 'ArrowRight'
  return key
}

export type FocusRegion = 'sidebar' | 'content'
/** Which input produced the current focus — mouse hover must NOT trigger
 * scroll-into-view (a user moving the mouse across a rail shouldn't yank the
 * page around); only deliberate keyboard/D-pad navigation should. */
export type FocusOrigin = 'keyboard' | 'mouse'
export interface FocusState {
  region: FocusRegion
  row: number
  col: number
  origin: FocusOrigin
}

type Activate = (row: number, col: number) => void
/** How Up/Down picks a column in the row it's moving to — the two
 * conventional spatial-navigation modes (confirmed via CSSWG's spatial-nav
 * explainer and common D-pad nav libraries): a uniform grid (same-size cells
 * in fixed columns, e.g. GridPage/SearchPage's 6-column poster grid) should
 * land in the SAME column directly above/below, like a spreadsheet; a set of
 * independently-scrollable rails of differing lengths (Home's rows) should
 * instead let each row remember its own last column, since "same column"
 * across differently-ordered rails is meaningless/disorienting. */
export type ColMode = 'carry' | 'remember'

interface FocusContextValue {
  focus: FocusState
  /** Mouse hover handlers call this — marks origin 'mouse' (no auto-scroll).
   * Pass the triggering event's clientX/clientY so a scroll-induced
   * mouseenter (pointer didn't actually move) can be told apart from a real
   * hover — see the implementation in FocusProvider for why. */
  setFocus: (f: { region: FocusRegion; row: number; col: number }, e?: { clientX: number; clientY: number }) => void
  /** Content screens call this on mount (and whenever their grid shape
   * changes, e.g. a season switch) with one row-length per row and an
   * activate callback keyed by (row, col). `colMode` defaults to 'carry'.
   * `resetToTop` (used internally by useRegisterNav for a component's first
   * call) snaps content focus to {row:0,col:0} instead of clamping the
   * carried-over position — see the implementation for why. */
  registerNav: (lengths: number[], activate: Activate, colMode?: ColMode, resetToTop?: boolean) => void
  /** Shell calls this once with the sidebar's flat item count + activate. */
  registerSidebar: (length: number, activate: Activate) => void
  /** Shell calls this whenever the active tab changes (mouse click, keyboard,
   * or a direct URL/query-param navigation) so that jumping back to the
   * sidebar (Left, or Up at the top of a page) lands on the actually-active
   * item instead of a stale keyboard-nav history row. */
  setActiveSidebarRow: (row: number) => void
  /** A screen (Detail, Player) can set this to handle Escape/Backspace as
   * "go back" instead of the default no-op. Cleared automatically on unmount
   * by the screen's own effect cleanup. */
  setOnEscape: (fn: (() => void) | null) => void
  /** The Player owns a completely different focus model (a local string like
   * 'scrub'/'skip'/'nextcard' rather than {region,row,col} — matches the
   * source design's app.jsx, which bails out of its shared key handler
   * entirely while a player is open: `if (playerRef.current) return`). Call
   * while mounted so this engine's global listener steps aside instead of
   * double-handling arrow keys/Enter. */
  setSuspended: (suspended: boolean) => void
}

const FocusContext = createContext<FocusContextValue | null>(null)

// Persists ONLY "keyboard focus was sitting in the sidebar, on this row"
// across a real page reload — sessionStorage (not localStorage), since this
// is "resume exactly where I left off in this browsing session," not
// something that should survive into a fresh session later. Content's own
// row/col deliberately does NOT round-trip here: it's meant to always start
// at the top on a new page mount, reload included (see registerNav's
// resetToTop) — the sidebar is the one piece of "which UI region has D-pad
// focus" worth remembering, since unlike content position, a reload
// otherwise silently drops the user back into content even if they were
// deliberately navigating via the sidebar the moment they reloaded.
const SIDEBAR_FOCUS_KEY = 'rstv_sidebar_focus_row'

function loadInitialFocus(): FocusState {
  try {
    const raw = sessionStorage.getItem(SIDEBAR_FOCUS_KEY)
    if (raw !== null) {
      const row = parseInt(raw, 10)
      if (Number.isFinite(row) && row >= 0) return { region: 'sidebar', row, col: 0, origin: 'keyboard' }
    }
  } catch {
    // sessionStorage unavailable -- just falls through to the normal default
  }
  return { region: 'content', row: 0, col: 0, origin: 'keyboard' }
}

export function FocusProvider({ children }: { children: ReactNode }) {
  const [focus, setFocusState] = useState<FocusState>(loadInitialFocus)
  const focusRef = useRef(focus)
  focusRef.current = focus

  const contentNavRef = useRef<{ lengths: number[]; activate: Activate; colMode: ColMode }>({
    lengths: [1],
    activate: () => {},
    colMode: 'carry',
  })
  const sidebarNavRef = useRef<{ length: number; activate: Activate }>({ length: 1, activate: () => {} })
  const onEscapeRef = useRef<(() => void) | null>(null)
  const suspendedRef = useRef(false)
  // Remembers where in the sidebar you last were, so jumping back to it
  // (via Left or Up-at-top-of-page) lands on the active tab instead of
  // always resetting to row 0.
  const lastSidebarRowRef = useRef(0)
  // Each row (rail) remembers its OWN last-focused column, keyed by row
  // index — moving Up/Down between rows previously just carried over
  // whichever column you happened to be at in the row you left, which felt
  // arbitrary/disorienting when rows have different lengths. Reset whenever
  // a screen (re)registers its nav shape (new page, or the same page's data
  // genuinely changed shape, e.g. a season switch) so stale memory from a
  // different screen/season never leaks in.
  const rowColMemoryRef = useRef<Record<number, number>>({})
  // Last known real cursor position, kept up to date by a page-wide
  // `mousemove` listener (below) independent of whatever element (if any) is
  // under the pointer — see setFocus for the comparison this feeds. A
  // listener-driven *boolean* "has the mouse moved" flag was tried first and
  // discarded: browsers fire mouseenter/mouseover BEFORE the mousemove for
  // the same pointer transition, so a flag armed only by mousemove wasn't set
  // yet by the time the very first genuine hover after a keyboard move
  // needed it, incorrectly blocking that hover. Tracking the raw *position*
  // instead of a flag sidesteps that: even though the transition's own
  // mousemove hasn't fired yet when its mouseenter runs, this ref still holds
  // wherever the pointer was from the *previous* movement, which is a
  // different position whenever the user actually moved the mouse — the
  // comparison doesn't need this specific transition's own mousemove to have
  // landed first. What genuinely needs the listener (not just per-hover
  // events) is the case a coordinate check alone can't cover: the pointer
  // resting over *empty, non-card* space when a keyboard-driven scroll first
  // brings a card under it — with no prior hover event there's no earlier
  // recorded position to compare against, so without this listener that
  // first scroll-induced hover always reads as "moved" and wins.
  const lastMousePosRef = useRef<{ x: number; y: number } | null>(null)

  const setFocus = useCallback((f: { region: FocusRegion; row: number; col: number }, e?: { clientX: number; clientY: number }) => {
    // Guards against a real, reproducible browser behavior: `alignRow`
    // scrolls the page on every arrow-key move, and when content scrolls
    // underneath a mouse cursor that never actually moved, the browser still
    // fires a fresh `mouseenter` on whatever card now sits under that
    // (unmoved) cursor position — which this function would otherwise treat
    // as a real hover and use to silently steal focus back from the
    // keyboard, landing it on whatever happened to be under the pointer
    // rather than the intended cell. Comparing this hover's coordinates
    // against the last known real position tells the two apart. This uses a
    // small distance threshold rather than exact equality deliberately: a
    // real physical mouse/trackpad is essentially never bit-for-bit
    // stationary — natural hand tremor alone produces a pixel or two of
    // jitter — so exact equality only reliably catches this in synthetic
    // (test) input, not a real pointing device; a few pixels is far below
    // any distance a genuine "move to a different card" hover travels.
    if (e) {
      const last = lastMousePosRef.current
      const dx = last ? last.x - e.clientX : Infinity
      const dy = last ? last.y - e.clientY : Infinity
      const moved = !last || dx * dx + dy * dy > MOUSE_JITTER_THRESHOLD_SQ
      lastMousePosRef.current = { x: e.clientX, y: e.clientY }
      if (!moved) return
    }
    setFocusState({ ...f, origin: 'mouse' })
  }, [])
  const setSuspended = useCallback((s: boolean) => {
    suspendedRef.current = s
  }, [])

  // resetToTop is true only for a component's very first registerNav call
  // (see useRegisterNav below) — i.e. an actual new page mounting, not a
  // within-page data update (sort/filter/poll-driven item-count change on a
  // page the user is already on, which should keep clamping the existing
  // position rather than yanking focus back to the top on every refetch).
  // Without this, focus state lives at the FocusProvider level (it's never
  // reset when a tab switches, since tabs mount/unmount as siblings under
  // the same provider) — so a user who scrolled deep into one page's
  // content and then switches to a completely different page would land
  // keyboard/D-pad control wherever that stale row/col happens to clamp to
  // on the new page, not at its top.
  const registerNav = useCallback(
    (lengths: number[], activate: Activate, colMode: ColMode = 'carry', resetToTop = false) => {
      contentNavRef.current = { lengths, activate, colMode }
      rowColMemoryRef.current = {}
      setFocusState((f) => {
        // Guard against BOTH branches below applies here, not just the
        // clamp one — `row`/`col` mean "which content grid cell" only when
        // region is 'content'; while region is 'sidebar' the very same
        // fields mean "which sidebar row" instead. A new page's registerNav
        // firing while the user is still navigating via the sidebar (a real
        // sequence: sidebar Up/Down auto-activates each tab it passes
        // through, per Sidebar's own design) must never touch them, or it
        // silently resets the sidebar's own focus row back to 0 instead of
        // leaving the user on whichever tab they'd actually navigated to.
        if (f.region !== 'content') return f
        if (resetToTop) {
          return f.row === 0 && f.col === 0 ? f : { ...f, row: 0, col: 0 }
        }
        const row = Math.min(f.row, Math.max(0, lengths.length - 1))
        const col = Math.min(f.col, Math.max(0, (lengths[row] || 1) - 1))
        return row === f.row && col === f.col ? f : { ...f, row, col }
      })
    },
    [],
  )

  const registerSidebar = useCallback((length: number, activate: Activate) => {
    sidebarNavRef.current = { length, activate }
  }, [])

  const setActiveSidebarRow = useCallback((row: number) => {
    lastSidebarRowRef.current = row
  }, [])

  const setOnEscape = useCallback((fn: (() => void) | null) => {
    onEscapeRef.current = fn
  }, [])

  useEffect(() => {
    function onMouseMove(e: MouseEvent) {
      lastMousePosRef.current = { x: e.clientX, y: e.clientY }
    }
    window.addEventListener('mousemove', onMouseMove)
    return () => window.removeEventListener('mousemove', onMouseMove)
  }, [])

  // Keeps sessionStorage in sync with "is keyboard focus currently in the
  // sidebar, on which row" — see loadInitialFocus above for why only this
  // (not content's row/col) round-trips across a reload.
  useEffect(() => {
    try {
      if (focus.region === 'sidebar') sessionStorage.setItem(SIDEBAR_FOCUS_KEY, String(focus.row))
      else sessionStorage.removeItem(SIDEBAR_FOCUS_KEY)
    } catch {
      // sessionStorage unavailable -- this is a nice-to-have, fails silently
    }
  }, [focus.region, focus.row])

  // Moves REAL DOM focus (not just the `.is-foc` CSS class) onto whichever
  // element `{region,row,col}` currently points at. This entire engine used
  // to be purely a visual simulation — `.is-foc` was only ever a className,
  // `document.activeElement` never moved — which works fine for our own
  // keydown listener, but embedded TV browsers (Vewd/Opera TV Store, and
  // Chromium's own built-in Spatial Navigation some of them expose) decide
  // whether to hand the D-pad to *their* native focus-movement engine (or,
  // on generic non-TV-aware pages, fall back to emulating an on-screen mouse
  // pointer instead) based on whether the page actually has real, focusable,
  // `:focus`-tracked elements — see the CSS3 UI spatial-navigation model and
  // Vewd/Opera's own "tweaking spatial navigation" guidance, both of which
  // operate on genuinely focusable elements, never on a CSS class alone. A
  // page whose focus state lives only in React/CSS is indistinguishable, to
  // the browser, from an arbitrary site with no keyboard support at all.
  // `preventScroll: true` avoids double-fighting `useAutoScrollRow`/`Rail`'s
  // own scroll-into-view, which already runs off this same state change.
  useEffect(() => {
    const el = document.querySelector<HTMLElement>('.is-foc')
    if (el && document.activeElement !== el) el.focus({ preventScroll: true })
  }, [focus.region, focus.row, focus.col])

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (suspendedRef.current) return
      const key = normalizeArrowKey(e)
      if (key === 'Escape' || key === 'Backspace') {
        // Only intercept Backspace as "back" outside of text inputs — typing
        // in the search box or a dialog field must keep deleting characters.
        const target = e.target as HTMLElement | null
        const typing = target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')
        if (key === 'Escape' || !typing) {
          if (onEscapeRef.current) {
            e.preventDefault()
            onEscapeRef.current()
          }
          return
        }
      }
      if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter'].includes(key)) return
      const target = e.target as HTMLElement | null
      const typing = target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')
      // Left/Right must keep moving the text cursor while actively typing
      // (e.g. the Search page's real <input>) — but Up/Down/Enter have no
      // native meaning in a single-line input, so they always drive D-pad
      // navigation even while it's focused. Search additionally blurs the
      // input once focus leaves its row (see SearchPage), so Left/Right
      // reach the results grid normally after that.
      if (typing && (key === 'ArrowLeft' || key === 'ArrowRight')) return
      e.preventDefault()

      const sidebar = sidebarNavRef.current
      const content = contentNavRef.current

      // Enter is a one-shot action, not a movement — fine to read the ref
      // synchronously (no rapid-repeat risk from holding the key down).
      if (key === 'Enter') {
        const f = focusRef.current
        if (f.region === 'sidebar') sidebar.activate(f.row, 0)
        else content.activate(f.row, f.col)
        return
      }

      // Every other key here MOVES focus. Computing "next" from a ref
      // snapshot (`focusRef.current`) and passing a plain object to
      // setFocusState was the actual cause of the reported "sometimes goes
      // backward / sometimes jumps two" jankiness: holding a key down (or
      // just pressing it quickly) fires several 'keydown' events before
      // React re-renders and refreshes that ref, so 2+ consecutive events
      // could read the SAME stale row/col and compute the SAME next state —
      // one of the presses effectively vanishes — while the ref catching up
      // mid-burst could just as easily make the next press jump by two.
      // Using the functional setState form fixes this: React guarantees
      // each call sees the true latest state, even several queued in the
      // same batch.
      setFocusState((f) => {
        if (f.region === 'sidebar') {
          if (key === 'ArrowUp') {
            const row = Math.max(0, f.row - 1)
            lastSidebarRowRef.current = row
            sidebar.activate(row, 0)
            return { region: 'sidebar', row, col: 0, origin: 'keyboard' }
          }
          if (key === 'ArrowDown') {
            const row = Math.min(sidebar.length - 1, f.row + 1)
            lastSidebarRowRef.current = row
            sidebar.activate(row, 0)
            return { region: 'sidebar', row, col: 0, origin: 'keyboard' }
          }
          if (key === 'ArrowRight') {
            return { region: 'content', row: 0, col: 0, origin: 'keyboard' }
          }
          return f
        }

        const lengths = content.lengths.length ? content.lengths : [1]
        // Picks the column to land on when moving from row `fromRow` (at
        // `fromCol`) to row `toRow` — see the ColMode doc comment above.
        const resolveCol = (fromRow: number, toRow: number, fromCol: number) => {
          if (content.colMode === 'remember') {
            rowColMemoryRef.current[fromRow] = fromCol
            return rowColMemoryRef.current[toRow] ?? 0
          }
          return fromCol
        }

        if (key === 'ArrowLeft') {
          if (f.col > 0) return { ...f, col: f.col - 1, origin: 'keyboard' }
          return { region: 'sidebar', row: lastSidebarRowRef.current, col: 0, origin: 'keyboard' }
        }
        if (key === 'ArrowRight') {
          const col = Math.min((lengths[f.row] || 1) - 1, f.col + 1)
          return { ...f, col, origin: 'keyboard' }
        }
        if (key === 'ArrowUp') {
          if (f.row > 0) {
            const nr = f.row - 1
            const col = resolveCol(f.row, nr, f.col)
            return { ...f, row: nr, col: Math.min(col, (lengths[nr] || 1) - 1), origin: 'keyboard' }
          }
          // Already at the top row of the page — jump straight to the menu
          // instead of doing nothing.
          return { region: 'sidebar', row: lastSidebarRowRef.current, col: 0, origin: 'keyboard' }
        }
        if (key === 'ArrowDown') {
          const nr = Math.min(lengths.length - 1, f.row + 1)
          if (nr === f.row) return f
          const col = resolveCol(f.row, nr, f.col)
          return { ...f, row: nr, col: Math.min(col, (lengths[nr] || 1) - 1), origin: 'keyboard' }
        }
        return f
      })
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const value: FocusContextValue = {
    focus,
    setFocus,
    registerNav,
    registerSidebar,
    setActiveSidebarRow,
    setOnEscape,
    setSuspended,
  }
  return <FocusContext.Provider value={value}>{children}</FocusContext.Provider>
}

export function useFocusEngine(): FocusContextValue {
  const ctx = useContext(FocusContext)
  if (!ctx) throw new Error('useFocusEngine must be used within FocusProvider')
  return ctx
}

/** Convenience for a content-region cell: is-foc class + hover-sets-focus. */
export function useCellFocus(row: number, col: number) {
  const { focus, setFocus } = useFocusEngine()
  const isFocused = focus.region === 'content' && focus.row === row && focus.col === col
  const onHover = useCallback(
    (e: { clientX: number; clientY: number }) => setFocus({ region: 'content', row, col }, e),
    [setFocus, row, col],
  )
  return { isFocused, onHover }
}

/** Registers a content screen's focusable grid shape + activate callback.
 * Call once per screen (deps array controls re-registration, e.g. on season
 * change) — mirrors app.jsx's `useEffect(() => registerNav(...), [deps])`. */
export function useRegisterNav(
  lengths: number[],
  activate: Activate,
  deps: unknown[],
  colMode: ColMode = 'carry',
) {
  const { registerNav } = useFocusEngine()
  // True only for this component instance's very first registration (a real
  // new-page mount) — later calls (deps changing while still mounted, e.g. a
  // sort/filter/poll-driven update) clamp the existing position instead of
  // resetting it. Scoped to this hook call site via useRef, so it correctly
  // re-arms on a genuine remount (a fresh useRef(false) per mount) without
  // needing to reset it manually.
  const mountedRef = useRef(false)
  useEffect(() => {
    registerNav(lengths, activate, colMode, !mountedRef.current)
    mountedRef.current = true
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)
}

/** Registers a screen's Escape/Backspace handler; cleared on unmount. */
export function useBackHandler(onBack: (() => void) | null) {
  const { setOnEscape } = useFocusEngine()
  useEffect(() => {
    setOnEscape(onBack)
    return () => setOnEscape(null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onBack])
}

/** Suspends the engine's global keydown listener for as long as the calling
 * component is mounted (Player owns its own key handling entirely). */
export function useSuspendFocusEngine() {
  const { setSuspended } = useFocusEngine()
  useEffect(() => {
    setSuspended(true)
    return () => setSuspended(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
}
