// "Auf TV abspielen" for the phone view — same protocol as the native apps
// (backend: web/cast.py). Which TV is the playback target (remembered per
// browser; none = play on this phone), its latest heartbeat, and the
// commands. A TV is any browser running the web app in screen mode.
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { apiFetch } from '../api/client'
import type { CastScreen, PlayItem } from './types'

const TARGET_KEY = 'rstv_cast_target'

export interface CastTarget {
  id: string
  name: string
}

function loadTarget(): CastTarget | null {
  try {
    const raw = localStorage.getItem(TARGET_KEY)
    const t = raw ? JSON.parse(raw) : null
    return t && typeof t.id === 'string' ? { id: t.id, name: String(t.name || 'Fernseher') } : null
  } catch {
    return null
  }
}

export function getScreens(): Promise<CastScreen[]> {
  return apiFetch<{ screens: CastScreen[] }>('/api/cast/screens').then((r) => r.screens)
}

function sendCommand(screenId: string, body: Record<string, unknown>): Promise<void> {
  return apiFetch<void>(`/api/cast/screens/${encodeURIComponent(screenId)}/command`, { method: 'POST', body })
}

interface CastContextValue {
  target: CastTarget | null
  /** Latest heartbeat of `target` (null while unknown). */
  targetScreen: CastScreen | null
  targetOffline: boolean
  select: (screen: CastScreen | null) => void
  play: (item: PlayItem) => Promise<void>
  toggle: () => void
  stop: () => void
  seekBy: (seconds: number) => void
  sheetOpen: boolean
  setSheetOpen: (open: boolean) => void
}

const CastContext = createContext<CastContextValue | null>(null)

export function CastProvider({ children }: { children: ReactNode }) {
  const [target, setTarget] = useState<CastTarget | null>(loadTarget)
  const [targetScreen, setTargetScreen] = useState<CastScreen | null>(null)
  const [targetOffline, setTargetOffline] = useState(false)
  const [sheetOpen, setSheetOpen] = useState(false)

  const select = useCallback((screen: CastScreen | null) => {
    const t = screen ? { id: screen.id, name: screen.name } : null
    setTarget(t)
    setTargetScreen(screen)
    setTargetOffline(false)
    try {
      if (t) localStorage.setItem(TARGET_KEY, JSON.stringify(t))
      else localStorage.removeItem(TARGET_KEY)
    } catch {
      // private mode
    }
  }, [])

  // Keep the target's now-playing state fresh for the remote bar.
  useEffect(() => {
    if (!target) return
    let stopped = false
    const tick = async () => {
      try {
        const match = (await getScreens()).find((s) => s.id === target.id) ?? null
        if (stopped) return
        setTargetScreen(match)
        setTargetOffline(match === null)
      } catch {
        // offline — keep the last state
      }
    }
    tick()
    const timer = setInterval(tick, 2000)
    return () => {
      stopped = true
      clearInterval(timer)
    }
  }, [target])

  const play = useCallback(
    async (item: PlayItem) => {
      if (!target) throw new Error('Kein Fernseher ausgewählt')
      await sendCommand(target.id, {
        type: 'play',
        episode_url: item.episodeUrl,
        series_title: item.seriesTitle,
        series_url: item.seriesUrl,
        season: item.season,
        episode_number: item.episodeNumber,
        episode_title: item.episodeTitle,
        absolute_episode_number: item.absoluteEpisodeNumber ?? undefined,
        language: item.language,
        provider: item.provider,
      })
    },
    [target],
  )

  const simple = useCallback(
    (body: Record<string, unknown>) => {
      if (target) sendCommand(target.id, body).catch(() => {})
    },
    [target],
  )

  const value = useMemo<CastContextValue>(
    () => ({
      target,
      targetScreen,
      targetOffline,
      select,
      play,
      toggle: () => simple({ type: 'toggle' }),
      stop: () => simple({ type: 'stop' }),
      seekBy: (seconds: number) => simple({ type: 'seek', delta: seconds }),
      sheetOpen,
      setSheetOpen,
    }),
    [target, targetScreen, targetOffline, select, play, simple, sheetOpen],
  )

  return <CastContext.Provider value={value}>{children}</CastContext.Provider>
}

export function useCast(): CastContextValue {
  const ctx = useContext(CastContext)
  if (!ctx) throw new Error('useCast must be used within CastProvider')
  return ctx
}
