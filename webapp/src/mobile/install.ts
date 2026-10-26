// "Als App installieren" hint for the phone view. Hidden once the page runs
// as an installed web app (display-mode standalone / iOS navigator.standalone).
// Chrome on Android offers a real install dialog via `beforeinstallprompt`
// (captured as early as possible — it fires once, right after load); Safari
// on iOS has no API for it, so there the hint explains Teilen → Zum
// Home-Bildschirm.
import { useEffect, useState } from 'react'

interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

let deferred: InstallPromptEvent | null = null
const listeners = new Set<() => void>()
const notify = () => listeners.forEach((l) => l())

/** Called from main.tsx before React renders. */
export function captureInstallPrompt(): void {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault() // we show our own hint instead of Chrome's mini-infobar
    deferred = e as InstallPromptEvent
    notify()
  })
  window.addEventListener('appinstalled', () => {
    deferred = null
    notify()
  })
}

export function isInstalled(): boolean {
  const nav = navigator as Navigator & { standalone?: boolean }
  try {
    return nav.standalone === true || window.matchMedia('(display-mode: standalone)').matches
  } catch {
    return false
  }
}

export type InstallPlatform = 'ios' | 'android' | 'other'

export function installPlatform(): InstallPlatform {
  const ua = navigator.userAgent
  if (/iPhone|iPad|iPod/.test(ua)) return 'ios'
  if (/Android/.test(ua)) return 'android'
  return 'other'
}

const DISMISS_KEY = 'rstv_install_hint_dismissed'
const REMIND_AFTER_MS = 14 * 24 * 3600 * 1000

function dismissedRecently(): boolean {
  try {
    const at = Number(localStorage.getItem(DISMISS_KEY) || 0)
    return Date.now() - at < REMIND_AFTER_MS
  } catch {
    return false
  }
}

export function dismissInstallHint(): void {
  try {
    localStorage.setItem(DISMISS_KEY, String(Date.now()))
  } catch {
    // private mode — the hint just comes back next time
  }
  notify()
}

/** Shows Chrome's install dialog; false if the browser doesn't offer one. */
export async function promptInstall(): Promise<boolean> {
  if (!deferred) return false
  const ev = deferred
  deferred = null
  await ev.prompt()
  const choice = await ev.userChoice.catch(() => null)
  notify()
  return choice?.outcome === 'accepted'
}

export interface InstallState {
  installed: boolean
  /** The hint banner should show (not installed, not dismissed lately). */
  showHint: boolean
  canPrompt: boolean
  platform: InstallPlatform
}

function snapshot(): InstallState {
  const installed = isInstalled()
  return { installed, showHint: !installed && !dismissedRecently(), canPrompt: deferred !== null, platform: installPlatform() }
}

export function useInstallState(): InstallState {
  const [state, setState] = useState(snapshot)
  useEffect(() => {
    const update = () => setState(snapshot())
    listeners.add(update)
    return () => {
      listeners.delete(update)
    }
  }, [])
  return state
}
