// Detects whether the app is running inside an actual TV browser, so
// GridPage (Serien/Anime/Filme) can switch to a Netflix-TV-app-style
// treatment — bigger tiles, bolder type, fewer columns — for 10-foot
// viewing. There's no reliable cross-browser "is this a TV" API, so this is
// User-Agent sniffing against known TV browser signatures, with a manual
// override (Settings) as the fallback for whatever it inevitably misses.

const TV_UA_RE = /Tizen|SmartTV|SMART-TV|WebOS|Web0S|CrKey|Android TV|GoogleTV|HbbTV|AFT[A-Z]|VIDAA/i

export function detectTvFromUA(ua: string): boolean {
  return TV_UA_RE.test(ua)
}

// Follows the app's existing rstv_* localStorage naming convention (see
// api/client.ts's rstv_token/rstv_profile_id). Absent = auto-detect.
const OVERRIDE_KEY = 'rstv_tv_mode'
export type TvOverride = 'on' | 'off' | null

export function getTvOverride(): TvOverride {
  try {
    const v = localStorage.getItem(OVERRIDE_KEY)
    return v === 'on' || v === 'off' ? v : null
  } catch {
    return null
  }
}

export function setTvOverride(v: TvOverride): void {
  try {
    if (v === null) localStorage.removeItem(OVERRIDE_KEY)
    else localStorage.setItem(OVERRIDE_KEY, v)
  } catch {
    // localStorage unavailable (private mode etc.) — override just won't persist
  }
  applyTvAttribute()
  notifyListeners()
}

export function computeIsTv(): boolean {
  const override = getTvOverride()
  return override !== null ? override === 'on' : detectTvFromUA(navigator.userAgent)
}

// Sets the CSS hook (`html[data-tv="true"]`, read directly by GridPage.css —
// no React re-render needed for the CSS side to react). Called synchronously
// at app init in main.tsx, before the first paint, so a real TV never
// flashes non-TV sizing for a frame.
export function applyTvAttribute(): void {
  document.documentElement.setAttribute('data-tv', String(computeIsTv()))
}

// Minimal pub-sub backing useIsTv() — only Settings' toggle display needs to
// re-render when this changes; nothing else subscribes.
const listeners = new Set<() => void>()
function notifyListeners() {
  for (const l of listeners) l()
}
export function subscribeTv(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}
