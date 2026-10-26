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
  appendGCast,
  endGCastSession,
  gcastNext,
  gcastSeekBy,
  gcastStop,
  gcastToggle,
  getGCastStatus,
  initGoogleCast,
  loadGCastQueue,
  requestGCastSession,
  subscribeGCast,
  type GCastMedia,
  type GCastStatus,
} from './googleCast'
import { absoluteUrl, findNextEpisode, resolveStream } from './resolve'
import { epCode } from './format'
import type { CastScreen, PlayItem } from './types'

const TARGET_KEY = 'rstv_cast_target'
// Like the TV/desktop player: jump to the next episode 30 s before the end
// (its 40 s "Nächste Folge" window minus the 10 s countdown).
const CAST_ADVANCE_REMAINING_S = 30

function castMedia(item: PlayItem, url: string, startTime: number): GCastMedia {
  return {
    url,
    title: item.seriesTitle,
    subtitle: epCode(item.season, item.episodeNumber) + (item.episodeTitle ? ` · ${item.episodeTitle}` : ''),
    startTime,
  }
}

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
  // What the Cast device is playing (it only knows URL + title), and the
  // episodes queued on it by URL — so the next one plays on the TV by
  // itself, and while this page is open it's topped up one at a time.
  const gcastItem = useRef<PlayItem | null>(null)
  const [, rerender] = useState(0) // the remote bar shows gcastItem
  const gcastQueue = useRef(new Map<string, PlayItem>())
  const nextQueuedFor = useRef(new Set<string>())
  const advancedFrom = useRef(new Set<string>())
  /** episode URL → its successor, once that's actually in the device's queue. */
  const queuedNext = useRef(new Map<string, PlayItem>())

  /** Puts the episode after `item` into the device's queue (once). */
  const queueNextAfter = useCallback(async (item: PlayItem) => {
    if (nextQueuedFor.current.has(item.episodeUrl)) return
    nextQueuedFor.current.add(item.episodeUrl)
    try {
      const next = await findNextEpisode(item)
      if (!next) return
      const stream = await resolveStream(next, { loginFree: true })
      const url = absoluteUrl(stream.url)
      await appendGCast(castMedia(next, url, 0))
      gcastQueue.current.set(url, next)
      queuedNext.current.set(item.episodeUrl, next)
    } catch {
      nextQueuedFor.current.delete(item.episodeUrl) // try again on the next status update
    }
  }, [])

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

  // Follow the device through its queue: a new item playing → that's our
  // current episode (the previous one counts as watched), top the queue up,
  // and skip ahead 30 s before the end like the desktop player does.
  useEffect(() => {
    if (!gcast.device || !gcast.contentId) return
    const playingItem = gcastQueue.current.get(gcast.contentId)
    const cur = gcastItem.current
    if (playingItem && cur && playingItem.episodeUrl !== cur.episodeUrl) {
      if (gcast.duration > 0) {
        saveProgress({
          episode_url: cur.episodeUrl,
          series_title: cur.seriesTitle,
          series_url: cur.seriesUrl,
          season: cur.season,
          episode_number: cur.episodeNumber,
          episode_title: cur.episodeTitle,
          position_seconds: gcast.duration,
          duration_seconds: gcast.duration,
          completed: true,
        }).catch(() => {})
      }
      gcastItem.current = playingItem
      rerender((n) => n + 1)
    }
    const now = gcastItem.current
    if (!now || gcast.state === 'idle') return
    queueNextAfter(now)
    const remaining = gcast.duration - gcast.position
    if (
      gcast.state === 'playing' &&
      gcast.duration > 60 &&
      remaining <= CAST_ADVANCE_REMAINING_S &&
      queuedNext.current.has(now.episodeUrl) &&
      !advancedFrom.current.has(now.episodeUrl)
    ) {
      advancedFrom.current.add(now.episodeUrl)
      gcastNext()
    }
  }, [gcast, queueNextAfter])

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
        const url = absoluteUrl(stream.url)
        gcastQueue.current = new Map([[url, item]])
        nextQueuedFor.current.clear()
        queuedNext.current.clear()
        advancedFrom.current.clear()
        gcastItem.current = item
        await loadGCastQueue([castMedia(item, url, resume)])
        queueNextAfter(item) // in the background: the next episode goes into the TV's queue
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
    [screenTarget, queueNextAfter],
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
