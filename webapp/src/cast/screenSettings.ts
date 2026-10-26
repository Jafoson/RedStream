// Per-browser screen-mode settings (Settings → Bildschirm).
import { detectTvFromUA } from '../tv/detectTv'

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

export function isScreenEnabled(): boolean {
  return read(ENABLED_KEY) !== '0'
}

export function setScreenEnabled(on: boolean): void {
  write(ENABLED_KEY, on ? '1' : '0')
  window.dispatchEvent(new Event('rstv-screen-settings'))
}

export function defaultScreenName(): string {
  const ua = navigator.userAgent
  if (detectTvFromUA(ua)) return 'Fernseher'
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
