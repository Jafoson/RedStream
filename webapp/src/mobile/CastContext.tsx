// "Auf TV abspielen" for the phone view. Two kinds of target:
// - a RedStream screen: any browser running the web app in screen mode,
//   remote-controlled through the backend (web/cast.py) — same protocol as
//   the native apps; remembered per browser;
// - a Google Cast device (Chromecast, Android TV / Google TV) via Chrome's
//   Cast SDK (googleCast.ts): the TV fetches the stream itself.
// None = play on this phone. The remote bar shows either kind the same way.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { apiFetch } from '../api/client'
import { getEpisodeProgress, saveProgress } from '../api/stream'
import {
  endGCastSession,
  gcastSeekBy,
  gcastStop,
  gcastToggle,
  getGCastStatus,
  initGoogleCast,
  loadGCastMedia,
  requestGCastSession,
  subscribeGCast,
  type GCastStatus,
} from './googleCast'
import { absoluteUrl, resolveStream } from './resolve'
import { epCode } from './format'
import type { CastScreen, PlayItem } from './types'

const TARGET_KEY = 'rstv_cast_target'

export interface CastTarget {
  id: string
  name: string
  kind: 'screen' | 'gcast'
}

function loadTarget(): CastTarget | null {
  try {
    const raw = localStorage.getItem(TARGET_KEY)
    const t = raw ? JSON.parse(raw) : null
    return t && typeof t.id === 'string' ? { id: t.id, name: String(t.name || 'Fernseher'), kind: 'screen' } : null
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
  /** Latest state of `target` for the remote bar (null while unknown). */
  targetScreen: CastScreen | null
  targetOffline: boolean
  select: (screen: CastScreen | null) => void
  /** Google Cast devices on the network (Chrome only). */
  gcastAvailable: boolean
  connectGCast: () => Promise<void>
  play: (item: PlayItem) => Promise<void>
  toggle: () => void
  stop: () => void
  seekBy: (seconds: number) => void
  sheetOpen: boolean
  setSheetOpen: (open: boolean) => void
}

const CastContext = createContext<CastContextValue | null>(null)

export function CastProvider({ children }: { children: ReactNode }) {
  const [screenTarget, setScreenTarget] = useState<CastTarget | null>(loadTarget)
  const [screenState, setScreenState] = useState<CastScreen | null>(null)
  const [screenOffline, setScreenOffline] = useState(false)
  const [sheetOpen, setSheetOpen] = useState(false)
  const [gcast, setGcast] = useState<GCastStatus>(getGCastStatus)
  // What the Cast device is playing (it only knows URL + title).
  const gcastItem = useRef<PlayItem | null>(null)

  useEffect(() => {
    initGoogleCast()
    return subscribeGCast(setGcast)
  }, [])

  const rememberScreen = (t: CastTarget | null) => {
    setScreenTarget(t)
    try {
      if (t) localStorage.setItem(TARGET_KEY, JSON.stringify({ id: t.id, name: t.name }))
      else localStorage.removeItem(TARGET_KEY)
    } catch {
      // private mode
    }
  }

  const select = useCallback((screen: CastScreen | null) => {
    if (getGCastStatus().device) endGCastSession()
    rememberScreen(screen ? { id: screen.id, name: screen.name, kind: 'screen' } : null)
    setScreenState(screen)
    setScreenOffline(false)
  }, [])

  const connectGCast = useCallback(async () => {
    await requestGCastSession()
    rememberScreen(null) // a connected Cast device is the target now
  }, [])

  const target: CastTarget | null = gcast.device ? { id: 'gcast', name: gcast.device, kind: 'gcast' } : screenTarget

  // Keep a RedStream screen's now-playing state fresh for the remote bar.
  useEffect(() => {
    if (!screenTarget || gcast.device) return
    let stopped = false
    const tick = async () => {
      try {
        const match = (await getScreens()).find((s) => s.id === screenTarget.id) ?? null
        if (stopped) return
        setScreenState(match)
        setScreenOffline(match === null)
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
  }, [screenTarget, gcast.device])

  // A Cast device doesn't report to the server — save its progress from here.
  useEffect(() => {
    if (!gcast.device) return
    const timer = setInterval(() => {
      const s = getGCastStatus()
      const it = gcastItem.current
      if (!it || s.state !== 'playing' || !s.duration) return
      saveProgress({
        episode_url: it.episodeUrl,
        series_title: it.seriesTitle,
        series_url: it.seriesUrl,
        season: it.season,
        episode_number: it.episodeNumber,
        episode_title: it.episodeTitle,
        position_seconds: s.position,
        duration_seconds: s.duration,
        completed: s.position / s.duration >= 0.9,
      }).catch(() => {})
    }, 10_000)
    return () => clearInterval(timer)
  }, [gcast.device])

  const play = useCallback(
    async (item: PlayItem) => {
      if (getGCastStatus().device) {
        const stream = await resolveStream(item, { loginFree: true })
        const p = await getEpisodeProgress(item.episodeUrl).catch(() => null)
        const resume = p && !p.completed && p.position_seconds > 30 && p.position_seconds < p.duration_seconds - 10 ? p.position_seconds : 0
        gcastItem.current = item
        await loadGCastMedia({
          url: absoluteUrl(stream.url),
          title: item.seriesTitle,
          subtitle: epCode(item.season, item.episodeNumber) + (item.episodeTitle ? ` · ${item.episodeTitle}` : ''),
          startTime: resume,
        })
        return
      }
      if (!screenTarget) throw new Error('Kein Fernseher ausgewählt')
      await sendCommand(screenTarget.id, {
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
    [screenTarget],
  )

  const simple = useCallback(
    (body: Record<string, unknown>) => {
      if (screenTarget) sendCommand(screenTarget.id, body).catch(() => {})
    },
    [screenTarget],
  )

  // The remote bar reads a CastScreen; for a Cast device build one locally.
  const targetScreen: CastScreen | null = gcast.device
    ? {
        id: 'gcast',
        name: gcast.device,
        profile_id: null,
        profile_name: null,
        online: true,
        state: {
          status: gcast.state,
          series_title: gcastItem.current?.seriesTitle,
          season: gcastItem.current?.season,
          episode_number: gcastItem.current?.episodeNumber,
          position: gcast.position,
          duration: gcast.duration,
        },
      }
    : screenState

  const isGcast = !!gcast.device
  const value = useMemo<CastContextValue>(
    () => ({
      target,
      targetScreen,
      targetOffline: isGcast ? false : screenOffline,
      select,
      gcastAvailable: gcast.available,
      connectGCast,
      play,
      toggle: () => (isGcast ? gcastToggle() : simple({ type: 'toggle' })),
      stop: () => (isGcast ? gcastStop() : simple({ type: 'stop' })),
      seekBy: (seconds: number) => (isGcast ? gcastSeekBy(seconds) : simple({ type: 'seek', delta: seconds })),
      sheetOpen,
      setSheetOpen,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [target?.id, target?.name, targetScreen, screenOffline, select, gcast, connectGCast, play, simple, sheetOpen],
  )

  return <CastContext.Provider value={value}>{children}</CastContext.Provider>
}

export function useCast(): CastContextValue {
  const ctx = useContext(CastContext)
  if (!ctx) throw new Error('useCast must be used within CastProvider')
  return ctx
}
