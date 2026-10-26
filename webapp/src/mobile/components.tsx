// Building blocks of the phone view (look of the native iOS/Android apps).
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getActiveProfileId } from '../api/client'
import { getScreens, useCast } from './CastContext'
import { epCode, formatTime } from './format'
import { MIcon, type MIconName } from './icons'
import type { CastScreen, PlayItem } from './types'

// ── Toast ───────────────────────────────────────────────────────────────────

const ToastCtx = createContext<(text: string) => void>(() => {})

export function MToastProvider({ children }: { children: ReactNode }) {
  const [text, setText] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const show = useCallback((t: string) => {
    setText(t)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => setText(null), 3500)
  }, [])
  return (
    <ToastCtx.Provider value={show}>
      {children}
      {text && <div className="m-toast">{text}</div>}
    </ToastCtx.Provider>
  )
}

export function useMToast() {
  return useContext(ToastCtx)
}

// ── Playback routing ────────────────────────────────────────────────────────

/** Plays an episode on the selected TV, or opens the phone player. */
export function usePlay() {
  const cast = useCast()
  const navigate = useNavigate()
  const toast = useMToast()
  return useCallback(
    (item: PlayItem, forcePhone = false) => {
      const target = cast.target
      if (target && !forcePhone) {
        cast
          .play(item)
          .then(() => toast(`Läuft auf ${target.name}: ${item.seriesTitle} ${epCode(item.season, item.episodeNumber)}`))
          .catch((e: unknown) => toast(`${target.name} nicht erreichbar: ${e instanceof Error ? e.message : e}`))
      } else {
        navigate('/abspielen', { state: item })
      }
    },
    [cast, navigate, toast],
  )
}

export function openSeries(navigate: ReturnType<typeof useNavigate>, url: string, title: string) {
  navigate(`/serie?url=${encodeURIComponent(url)}&title=${encodeURIComponent(title)}`)
}

// ── Chrome ──────────────────────────────────────────────────────────────────

export function TopBar({ title, large = true, back }: { title: string; large?: boolean; back?: boolean }) {
  const navigate = useNavigate()
  const cast = useCast()
  return (
    <header className={'m-topbar' + (large ? ' m-topbar--large' : '')}>
      {back && (
        <button
          type="button"
          className="m-icon-btn"
          aria-label="Zurück"
          onClick={() => (window.history.state?.idx > 0 ? navigate(-1) : navigate('/'))}
        >
          <MIcon name="back" />
        </button>
      )}
      <h1 className="m-topbar__title">{title}</h1>
      <button
        type="button"
        className={'m-icon-btn' + (cast.target ? ' m-accent' : '')}
        aria-label="Auf TV abspielen"
        onClick={() => cast.setSheetOpen(true)}
      >
        <MIcon name={cast.target ? 'castOn' : 'cast'} />
      </button>
    </header>
  )
}

export function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <h2 className="m-section">
      <span className="m-section__bar" />
      {children}
    </h2>
  )
}

export function Spinner() {
  return (
    <div className="m-center">
      <div className="m-spinner" />
    </div>
  )
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="m-error">
      <p>{message}</p>
      {onRetry && (
        <button type="button" className="m-btn m-btn--primary" onClick={onRetry}>
          Erneut versuchen
        </button>
      )}
    </div>
  )
}

export function Poster({ title, image, className }: { title: string; image?: string | null; className?: string }) {
  const [failed, setFailed] = useState(false)
  return (
    <div className={'m-poster ' + (className ?? '')}>
      <span className="m-poster__initial">{title.slice(0, 1).toUpperCase()}</span>
      {image && !failed && <img src={image} alt="" loading="lazy" onError={() => setFailed(true)} />}
    </div>
  )
}

export function PosterCard({ title, image, onClick }: { title: string; image?: string | null; onClick: () => void }) {
  return (
    <button type="button" className="m-card" onClick={onClick}>
      <Poster title={title} image={image} />
      <span className="m-card__title">{title}</span>
    </button>
  )
}

export function PosterGrid({ items }: { items: { title: string; url: string; poster_url?: string | null }[] }) {
  const navigate = useNavigate()
  return (
    <div className="m-grid">
      {items.map((it) => (
        <PosterCard key={it.url} title={it.title} image={it.poster_url} onClick={() => openSeries(navigate, it.url, it.title)} />
      ))}
    </div>
  )
}

export function ProgressLine({ fraction, className }: { fraction: number; className?: string }) {
  return (
    <div className={'m-progress ' + (className ?? '')}>
      <div className="m-progress__fill" style={{ width: `${Math.max(0, Math.min(1, fraction)) * 100}%` }} />
    </div>
  )
}

// ── Bottom navigation ───────────────────────────────────────────────────────

export type MTab = 'start' | 'entdecken' | 'suche' | 'liste' | 'mehr'

export const M_TABS: { tab: MTab; label: string; icon: MIconName }[] = [
  { tab: 'start', label: 'Start', icon: 'home' },
  { tab: 'entdecken', label: 'Entdecken', icon: 'explore' },
  { tab: 'suche', label: 'Suche', icon: 'search' },
  { tab: 'liste', label: 'Meine Liste', icon: 'bookmark' },
  { tab: 'mehr', label: 'Mehr', icon: 'person' },
]

export function TabBar({ active }: { active: MTab | null }) {
  const navigate = useNavigate()
  return (
    <nav className="m-tabbar">
      {M_TABS.map((t) => (
        <button
          key={t.tab}
          type="button"
          className={'m-tabbar__item' + (t.tab === active ? ' active' : '')}
          onClick={() => navigate(t.tab === 'start' ? '/' : `/?tab=${t.tab}`)}
        >
          <span className="m-tabbar__icon">
            <MIcon name={t.icon} />
          </span>
          <span>{t.label}</span>
        </button>
      ))}
    </nav>
  )
}

// ── Cast: target sheet + remote bar ─────────────────────────────────────────

/** Safari: AirPlay works from the player (see PlayerScreen). */
const AIRPLAY = typeof window !== 'undefined' && 'WebKitPlaybackTargetAvailabilityEvent' in window

function describe(screen: CastScreen): string {
  const st = screen.state || {}
  let what = '…'
  if (st.series_title) {
    what = st.season != null && st.episode_number != null ? `${st.series_title} · ${epCode(st.season, st.episode_number)}` : st.series_title
  }
  switch (st.status) {
    case 'playing':
      return `Spielt: ${what}`
    case 'paused':
      return `Pausiert: ${what}`
    case 'buffering':
      return `Lädt: ${what}`
    case 'loading':
      return `Wird gestartet: ${what}`
    default:
      return 'Bereit'
  }
}

export function CastSheet() {
  const cast = useCast()
  const close = () => cast.setSheetOpen(false)
  const screens = useQuery({ queryKey: ['m-cast-screens'], queryFn: getScreens, refetchInterval: 3000, enabled: cast.sheetOpen })
  useEffect(() => {
    if (!cast.sheetOpen) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cast.sheetOpen])
  if (!cast.sheetOpen) return null
  const mine = getActiveProfileId()
  const list = [...(screens.data ?? [])].sort((a, b) => Number(b.profile_id === mine) - Number(a.profile_id === mine))
  return (
    <div className="m-sheet-backdrop" onClick={close}>
      <div className="m-sheet" role="dialog" aria-label="Abspielen auf" onClick={(e) => e.stopPropagation()}>
        <div className="m-sheet__handle" />
        <h2 className="m-sheet__title">Abspielen auf</h2>
        <TargetRow
          icon="phone"
          title="Dieses Handy"
          subtitle="Direkt hier abspielen"
          selected={cast.target === null}
          onClick={() => {
            cast.select(null)
            close()
          }}
        />
        {(cast.gcastAvailable || cast.target?.kind === 'gcast') && (
          <TargetRow
            icon="cast"
            title={cast.target?.kind === 'gcast' ? cast.target.name : 'Chromecast / Android TV'}
            subtitle={cast.target?.kind === 'gcast' ? 'Google Cast · verbunden' : 'Google Cast · Gerät in der Nähe wählen'}
            selected={cast.target?.kind === 'gcast'}
            onClick={() => {
              if (cast.target?.kind === 'gcast') close()
              else cast.connectGCast().then(close, () => {})
            }}
          />
        )}
        {AIRPLAY && (
          <TargetRow
            icon="airplay"
            title="Apple TV (AirPlay)"
            subtitle="Folge auf dem iPhone starten und im Player auf AirPlay tippen"
            selected={false}
            onClick={close}
          />
        )}
        {screens.isLoading && <Spinner />}
        {screens.isError && <p className="m-error-text">Fernseher konnten nicht geladen werden.</p>}
        {screens.data && list.length === 0 && (
          <p className="m-muted m-pad">
            Kein Fernseher online. Öffne RedStream im Browser des Fernsehers – unter Einstellungen → Bildschirm muss „Als
            Bildschirm verfügbar“ an sein.
          </p>
        )}
        {list.map((s) => (
          <TargetRow
            key={s.id}
            icon="tv"
            title={s.name + (s.profile_id != null && s.profile_id === mine ? '  · dein Profil' : '')}
            subtitle={(s.profile_name ? `Profil ${s.profile_name} · ` : '') + describe(s)}
            selected={cast.target?.kind === 'screen' && cast.target.id === s.id}
            onClick={() => {
              cast.select(s)
              close()
            }}
          />
        ))}
      </div>
    </div>
  )
}

function TargetRow(props: { icon: MIconName; title: string; subtitle: string; selected: boolean; onClick: () => void }) {
  return (
    <button type="button" className={'m-target' + (props.selected ? ' selected' : '')} onClick={props.onClick}>
      <MIcon name={props.icon} className="m-target__icon" />
      <span className="m-target__text">
        <strong>{props.title}</strong>
        <span>{props.subtitle}</span>
      </span>
      {props.selected && <MIcon name="checkCircle" className="m-accent" />}
    </button>
  )
}

export function RemoteBar() {
  const cast = useCast()
  const target = cast.target
  if (!target) return null
  const screen = cast.targetScreen
  const st = screen?.state
  const active = !!st?.status && st.status !== 'idle'
  const playing = st?.status === 'playing' || st?.status === 'buffering'
  let line = 'Bereit – wähle eine Folge'
  if (cast.targetOffline) line = 'Offline – Browser am TV geöffnet?'
  else if (!screen) line = 'Verbinde…'
  else if (active) line = `${describe(screen)}  ${formatTime(st?.position)} / ${formatTime(st?.duration)}`
  return (
    <div className="m-remote">
      {active && (st?.duration ?? 0) > 0 && <ProgressLine fraction={(st?.position ?? 0) / (st?.duration || 1)} className="m-remote__progress" />}
      <div className="m-remote__row">
        <MIcon name={target.kind === 'gcast' ? 'castOn' : 'tv'} className="m-accent m-remote__tv" />
        <button type="button" className="m-remote__text" onClick={() => cast.setSheetOpen(true)}>
          <strong>{target.name}</strong>
          <span>{line}</span>
        </button>
        {active && (
          <>
            <button type="button" className="m-icon-btn" aria-label="10 Sek. zurück" onClick={() => cast.seekBy(-10)}>
              <MIcon name="replay10" />
            </button>
            <button type="button" className="m-icon-btn" aria-label={playing ? 'Pause' : 'Abspielen'} onClick={cast.toggle}>
              <MIcon name={playing ? 'pause' : 'play'} />
            </button>
            <button type="button" className="m-icon-btn" aria-label="10 Sek. vor" onClick={() => cast.seekBy(10)}>
              <MIcon name="forward10" />
            </button>
            <button type="button" className="m-icon-btn" aria-label="Stopp" onClick={cast.stop}>
              <MIcon name="stop" />
            </button>
          </>
        )}
      </div>
    </div>
  )
}
