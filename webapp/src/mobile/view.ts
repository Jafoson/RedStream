// Phone view: on a phone the web app switches to the same layout as the
// native iOS/Android apps (bottom tabs, touch player, "Auf TV abspielen")
// instead of the TV/desktop layout. Detected from the User-Agent / pointer +
// screen size; a per-browser override (Mehr → Ansicht, Settings → Anzeige)
// wins over detection.
import { useSyncExternalStore } from 'react'
import { detectTvFromUA } from '../tv/detectTv'

const KEY = 'rstv_view'
export type ViewOverride = 'mobile' | 'classic' | null

/** A phone (not a tablet, not a TV) — what the auto-detection says. */
export function isPhoneDevice(): boolean {
  const ua = navigator.userAgent
  if (detectTvFromUA(ua)) return false
  if (/iPhone|iPod/.test(ua)) return true
  if (/Android/.test(ua) && /Mobile/.test(ua)) return true
  try {
    return window.matchMedia('(pointer: coarse)').matches && Math.min(window.screen.width, window.screen.height) < 600
  } catch {
    return false
  }
}

export function getViewOverride(): ViewOverride {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'mobile' || v === 'classic' ? v : null
  } catch {
    return null
  }
}

const listeners = new Set<() => void>()

export function setViewOverride(v: ViewOverride): void {
  try {
    if (v === null) localStorage.removeItem(KEY)
    else localStorage.setItem(KEY, v)
  } catch {
    // private mode — the choice just won't survive a reload
  }
  applyMobileAttribute()
  for (const l of listeners) l()
}

export function computeMobileView(): boolean {
  const o = getViewOverride()
  return o !== null ? o === 'mobile' : isPhoneDevice()
}

/** `html[data-mobile]` — set before the first paint (main.tsx). */
export function applyMobileAttribute(): void {
  document.documentElement.setAttribute('data-mobile', String(computeMobileView()))
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function useMobileView(): boolean {
  return useSyncExternalStore(subscribe, computeMobileView)
}
