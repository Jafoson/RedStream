// Per-browser screen-mode settings (Settings → Bildschirm).
import { detectTvFromUA } from '../tv/detectTv'
import { computeMobileView } from '../mobile/view'

const ENABLED_KEY = 'rstv_screen_enabled'
const NAME_KEY = 'rstv_screen_name'
const ID_KEY = 'rstv_screen_id'

function read(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function write(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    // private mode etc.
  }
}

/** On unless switched off — except in the phone view, where the phone is
 * the remote control and only becomes a screen when switched on. */
export function isScreenEnabled(): boolean {
  const v = read(ENABLED_KEY)
  return v === null ? !computeMobileView() : v !== '0'
}

export function setScreenEnabled(on: boolean): void {
  write(ENABLED_KEY, on ? '1' : '0')
  window.dispatchEvent(new Event('rstv-screen-settings'))
}

export function defaultScreenName(): string {
  const ua = navigator.userAgent
  if (detectTvFromUA(ua)) return 'Fernseher'
  if (/iPhone/.test(ua)) return 'iPhone'
  const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Windows/.test(ua) ? 'Windows' : /Mac OS X/.test(ua) ? 'Mac' : /Linux/.test(ua) ? 'Linux' : ''
  return os ? `Browser (${os})` : 'Browser'
}

export function getScreenName(): string {
  return read(NAME_KEY)?.trim() || defaultScreenName()
}

export function setScreenName(name: string): void {
  write(NAME_KEY, name.trim() ? name.trim().slice(0, 60) : null)
  window.dispatchEvent(new Event('rstv-screen-settings'))
}

export function getScreenId(): string | null {
  return read(ID_KEY)
}

export function setScreenId(id: string | null): void {
  write(ID_KEY, id)
}
