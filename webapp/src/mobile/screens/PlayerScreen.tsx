// Phone player: same behaviour as the native apps' players — downloaded
// episodes from the server's disk, everything else via the direct-stream
// relay; resume, progress every 10 s, next episode at the end, language
// menu, and "Auf TV" hands the episode over at the current position.
import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { HlsPlayer } from '../../components/player/HlsPlayer'
import { resolveLiveStream } from '../../api/live'
import { getEpisodes, getProviders, getSeasons, setSeriesLanguage } from '../../api/series'
import { getEpisodeProgress, getStreamUrl, saveProgress } from '../../api/stream'
import { useCast } from '../CastContext'
import { epCode, formatTime, languageLabel, sortLanguages } from '../format'
import { MIcon } from '../icons'
import type { PlayItem } from '../types'

const RESUME_MIN_SECONDS = 30
const COMPLETED_RATIO = 0.9

interface Resolved {
  url: string
  kind: 'hls' | 'file'
  next: PlayItem | null
}

/** Finds the episode on the server's disk and the episode after it. */
async function lookupSeason(item: PlayItem) {
  const season = (await getSeasons(item.seriesUrl)).find((s) => s.season_number === item.season)
  if (!season) return { ep: null, next: null }
  const eps = await getEpisodes(season.url)
  const idx = eps.findIndex((e) => e.url === item.episodeUrl || e.episode_number === item.episodeNumber)
  if (idx < 0) return { ep: null, next: null }
  const n = eps[idx + 1]
  const next: PlayItem | null = n
    ? {
        ...item,
        episodeUrl: n.url,
        episodeNumber: n.episode_number,
        episodeTitle: (n.title_de || n.title_en || '').trim() || undefined,
        absoluteEpisodeNumber: n.absolute_episode_number,
        folder: n.downloaded ? n.folder : null,
      }
    : null
  return { ep: eps[idx], next }
}

async function resolve(item: PlayItem, allowDownloaded: boolean): Promise<Resolved> {
  const { ep, next } = await lookupSeason(item).catch(() => ({ ep: null, next: null }))
  const folder = allowDownloaded ? item.folder || (ep?.downloaded ? ep.folder : null) : null
  if (folder) {
    try {
      const url = await getStreamUrl({ folder, season: item.season, episode: item.episodeNumber })
      return { url, kind: 'hls', next }
    } catch {
      // not on disk after all — stream it
    }
  }
  const live = await resolveLiveStream({ episodeUrl: item.episodeUrl, language: item.language, provider: item.provider })
  return { url: live.url, kind: live.kind, next }
}

export function PlayerScreen() {
  const location = useLocation()
  const navigate = useNavigate()
  const cast = useCast()
  const initial = location.state as PlayItem | null
  const [item, setItem] = useState<PlayItem | null>(initial)
  const [load, setLoad] = useState({ key: 0, startAt: null as number | null, allowDownloaded: true })
  const [resolved, setResolved] = useState<Resolved | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [languages, setLanguages] = useState<string[]>([])
  const [controls, setControls] = useState(true)
  const [langMenu, setLangMenu] = useState(false)
  const [playing, setPlaying] = useState(false)
  const [time, setTime] = useState({ current: 0, duration: 0 })
  const [scrub, setScrub] = useState<number | null>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const stageRef = useRef<HTMLDivElement>(null)
  const itemRef = useRef(item)
  itemRef.current = item
  const resumeRef = useRef<number | null>(null)
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const close = useCallback(() => {
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
    if (window.history.state?.idx > 0) navigate(-1)
    else navigate('/', { replace: true })
  }, [navigate])

  const save = useCallback((completed = false) => {
    const v = videoRef.current
    const it = itemRef.current
    if (!v || !it || !v.duration || !Number.isFinite(v.duration)) return
    const done = completed || v.currentTime / v.duration >= COMPLETED_RATIO
    saveProgress({
      episode_url: it.episodeUrl,
      series_title: it.seriesTitle,
      series_url: it.seriesUrl,
      season: it.season,
      episode_number: it.episodeNumber,
      episode_title: it.episodeTitle,
      position_seconds: v.currentTime,
      duration_seconds: v.duration,
      completed: done,
    }).catch(() => {})
  }, [])

  // Resolve + start the current item.
  useEffect(() => {
    if (!item) return
    let cancelled = false
    setResolved(null)
    setError(null)
    ;(async () => {
      try {
        const r = await resolve(item, load.allowDownloaded)
        if (cancelled) return
        let resume = load.startAt
        if (resume === null) {
          const p = await getEpisodeProgress(item.episodeUrl).catch(() => null)
          if (p && !p.completed && p.position_seconds > RESUME_MIN_SECONDS && p.position_seconds < p.duration_seconds - 10) {
            resume = p.position_seconds
          }
        }
        resumeRef.current = resume
        if (!cancelled) setResolved(r)
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Folge konnte nicht geladen werden')
      }
      const langs = await getProviders(item.episodeUrl).catch(() => null)
      if (!cancelled && langs) setLanguages(sortLanguages(Object.keys(langs)))
    })()
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [load.key])

  // Progress every 10 s while playing, and when leaving.
  useEffect(() => {
    const timer = setInterval(() => {
      if (videoRef.current && !videoRef.current.paused) save()
    }, 10_000)
    return () => {
      clearInterval(timer)
      save()
    }
  }, [save])

  const scheduleHide = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current)
    hideTimer.current = setTimeout(() => {
      if (videoRef.current && !videoRef.current.paused) setControls(false)
    }, 4000)
  }, [])

  useEffect(() => {
    if (!resolved) return
    const v = videoRef.current
    if (!v) return
    const onTime = () => setTime({ current: v.currentTime, duration: Number.isFinite(v.duration) ? v.duration : 0 })
    const onPlay = () => {
      setPlaying(true)
      scheduleHide()
    }
    const onPause = () => {
      setPlaying(false)
      setControls(true)
      save()
    }
    const onMeta = () => {
      if (resumeRef.current) v.currentTime = resumeRef.current
      resumeRef.current = null
      v.play().catch(() => setPlaying(false))
    }
    const onEnded = () => {
      save(true)
      if (resolved.next) {
        setItem(resolved.next)
        setLoad((l) => ({ key: l.key + 1, startAt: null, allowDownloaded: true }))
      }
    }
    v.addEventListener('timeupdate', onTime)
    v.addEventListener('durationchange', onTime)
    v.addEventListener('play', onPlay)
    v.addEventListener('pause', onPause)
    v.addEventListener('loadedmetadata', onMeta)
    v.addEventListener('ended', onEnded)
    return () => {
      v.removeEventListener('timeupdate', onTime)
      v.removeEventListener('durationchange', onTime)
      v.removeEventListener('play', onPlay)
      v.removeEventListener('pause', onPause)
      v.removeEventListener('loadedmetadata', onMeta)
      v.removeEventListener('ended', onEnded)
    }
  }, [resolved, save, scheduleHide])

  if (!item) {
    return (
      <div className="m-player">
        <div className="m-player__center">
          <p>Keine Folge ausgewählt.</p>
          <button type="button" className="m-btn m-btn--outline" onClick={() => navigate('/', { replace: true })}>
            Zur Startseite
          </button>
        </div>
      </div>
    )
  }

  const toggleControls = () => {
    setControls((v) => !v)
    setLangMenu(false)
    scheduleHide()
  }
  const togglePlay = () => {
    const v = videoRef.current
    if (!v) return
    if (v.paused) v.play().catch(() => {})
    else v.pause()
  }
  const skip = (delta: number) => {
    const v = videoRef.current
    if (v && v.duration) v.currentTime = Math.max(0, Math.min(v.duration - 1, v.currentTime + delta))
    scheduleHide()
  }
  const switchLanguage = (lang: string) => {
    setLangMenu(false)
    if (lang === item.language) return
    save()
    const position = videoRef.current?.currentTime ?? null
    // A file on disk might be in the old language.
    setItem({ ...item, language: lang, provider: undefined, folder: null })
    setSeriesLanguage(item.seriesUrl, lang).catch(() => {})
    setLoad((l) => ({ key: l.key + 1, startAt: position, allowDownloaded: false }))
  }
  const toTv = () => {
    if (!cast.target) {
      cast.setSheetOpen(true)
      return
    }
    // Hand over: save the position, the TV resumes from it.
    save()
    videoRef.current?.pause()
    const handoff = item
    setTimeout(() => cast.play(handoff).catch(() => {}), 600) // let the progress save land first
    close()
  }
  const fullscreen = () => {
    const v = videoRef.current as (HTMLVideoElement & { webkitEnterFullscreen?: () => void }) | null
    const stage = stageRef.current
    if (stage?.requestFullscreen) {
      stage
        .requestFullscreen()
        .then(() => (screen.orientation as ScreenOrientation & { lock?: (o: string) => Promise<void> }).lock?.('landscape'))
        .catch(() => v?.webkitEnterFullscreen?.())
    } else {
      // iPhone Safari: only the video element itself can go full screen.
      v?.webkitEnterFullscreen?.()
    }
  }

  const shown = controls || !resolved || !!error
  const current = scrub ?? time.current

  return (
    <div className="m-player" ref={stageRef}>
      {resolved && (
        <HlsPlayer
          key={resolved.url}
          ref={videoRef}
          src={resolved.url}
          kind={resolved.kind}
          onFatalError={(reason) => setError(`Wiedergabe fehlgeschlagen: ${reason}`)}
        />
      )}
      <div className={'m-player__tap' + (shown ? ' shown' : '')} onClick={toggleControls} />

      {!resolved && !error && (
        <div className="m-player__center">
          <div className="m-spinner" />
          <p>Stream wird vorbereitet…</p>
        </div>
      )}
      {error && (
        <div className="m-player__center">
          <p className="m-error-text">{error}</p>
          <div className="m-row">
            <button type="button" className="m-btn m-btn--primary" onClick={() => setLoad((l) => ({ ...l, key: l.key + 1 }))}>
              Erneut versuchen
            </button>
            <button type="button" className="m-btn m-btn--outline" onClick={close}>
              Schließen
            </button>
          </div>
        </div>
      )}

      {shown && (
        <>
          <div className="m-player__top">
            <button type="button" className="m-icon-btn" aria-label="Zurück" onClick={close}>
              <MIcon name="back" />
            </button>
            <div className="m-player__title">
              <strong>{item.seriesTitle}</strong>
              <span>
                {epCode(item.season, item.episodeNumber)}
                {item.episodeTitle ? ` · ${item.episodeTitle}` : ''}
              </span>
            </div>
            {languages.length > 0 && (
              <div className="m-player__lang">
                <button type="button" className="m-icon-btn" aria-label="Sprache" onClick={() => setLangMenu((v) => !v)}>
                  <MIcon name="translate" />
                </button>
                {langMenu && (
                  <div className="m-menu m-menu--right">
                    {languages.map((l) => (
                      <button key={l} type="button" onClick={() => switchLanguage(l)}>
                        <span className="m-menu__check">{l === item.language && <MIcon name="check" size={18} />}</span>
                        {languageLabel(l)}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
            <button type="button" className="m-btn m-btn--ghost" onClick={toTv}>
              <MIcon name="tv" size={20} />
              {cast.target ? `Auf ${cast.target.name}` : 'Auf TV'}
            </button>
          </div>

          {resolved && !error && (
            <div className="m-player__middle">
              <button type="button" className="m-icon-btn m-icon-btn--big" aria-label="10 Sek. zurück" onClick={() => skip(-10)}>
                <MIcon name="replay10" size={40} />
              </button>
              <button type="button" className="m-player__play" aria-label={playing ? 'Pause' : 'Abspielen'} onClick={togglePlay}>
                <MIcon name={playing ? 'pause' : 'play'} size={40} />
              </button>
              <button type="button" className="m-icon-btn m-icon-btn--big" aria-label="10 Sek. vor" onClick={() => skip(10)}>
                <MIcon name="forward10" size={40} />
              </button>
            </div>
          )}

          {resolved && !error && (
            <div className="m-player__bottom">
              <input
                type="range"
                className="m-player__seek"
                min={0}
                max={Math.max(time.duration, 1)}
                step={1}
                value={current}
                style={{ ['--fill' as string]: `${time.duration ? (current / time.duration) * 100 : 0}%` }}
                onChange={(e) => {
                  setScrub(Number(e.target.value))
                  if (hideTimer.current) clearTimeout(hideTimer.current)
                }}
                onPointerUp={() => {
                  if (scrub !== null && videoRef.current) videoRef.current.currentTime = scrub
                  setScrub(null)
                  scheduleHide()
                }}
                onKeyUp={() => {
                  if (scrub !== null && videoRef.current) videoRef.current.currentTime = scrub
                  setScrub(null)
                }}
              />
              <div className="m-player__times">
                <span>
                  {formatTime(current)} <span className="m-dim">· {formatTime(time.duration)}</span>
                </span>
                <button type="button" className="m-icon-btn" aria-label="Vollbild" onClick={fullscreen}>
                  <MIcon name="fullscreen" />
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  )
}
