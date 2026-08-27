import type { SeriesDetail } from '../../api/series'
import { Icon } from '../layout/icons'
import { useCellFocus } from '../../tv/FocusEngine'
import './HeroSection.css'

export interface HeroSectionProps {
  detail: SeriesDetail
  onBack: () => void
  playLabel: string
  onPlay: () => void
  onRestart: () => void
  inWatchlist: boolean
  onToggleWatchlist: () => void
  language: string | null
  onOpenLanguage: () => void
  autosyncEnabled: boolean
  onToggleAutosync: () => void
}

function ActionButton({
  col,
  className,
  onClick,
  children,
}: {
  col: number
  className: string
  onClick: () => void
  children: React.ReactNode
}) {
  const { isFocused, onHover } = useCellFocus(0, col)
  return (
    <button type="button" className={className + (isFocused ? ' is-foc' : '')} onMouseEnter={onHover} onClick={onClick}>
      {children}
    </button>
  )
}

export function HeroSection({
  detail,
  onBack,
  playLabel,
  onPlay,
  onRestart,
  inWatchlist,
  onToggleWatchlist,
  language,
  onOpenLanguage,
  autosyncEnabled,
  onToggleAutosync,
}: HeroSectionProps) {
  const bg = detail.backdrop_url || detail.poster_url
  return (
    <div className="detail-hero row-anchor" data-row="0">
      {/* Quoted: proxied cover/backdrop URLs can carry literal parentheses
          (encodeURIComponent leaves "(" ")" unescaped), which break an
          unquoted CSS url() token — see PlayerControls.tsx's thumbnail-sprite
          fix for the same class of bug. */}
      {bg && <div className="detail-bg" style={{ backgroundImage: `url("${bg}")` }} />}
      <div className="poster-grain" />
      <div className="detail-shade" />
      <ActionButton col={0} className="back-btn" onClick={onBack}>
        <Icon name="back" w={18} />
        Zurück
      </ActionButton>
      <div className="detail-inner">
        <h1 className="detail-title">{detail.title}</h1>
        <div className="detail-meta">
          {detail.release_year && <span>{detail.release_year}</span>}
          {detail.release_year && <span className="chip-dot" />}
          {detail.genres.map((g) => (
            <span key={g} className="genre-tag">
              {g}
            </span>
          ))}
        </div>
        {detail.description && <p className="detail-desc">{detail.description}</p>}
        <div className="detail-actions">
          <ActionButton col={1} className="btn btn-primary" onClick={onPlay}>
            <Icon name="play" w={20} />
            {playLabel}
          </ActionButton>
          <ActionButton col={2} className="btn btn-ghost" onClick={onRestart}>
            <Icon name="skipnext" w={20} />
            Von vorne
          </ActionButton>
          <ActionButton col={3} className={'btn btn-ghost' + (inWatchlist ? ' on' : '')} onClick={onToggleWatchlist}>
            <Icon name="heart" w={20} />
            {inWatchlist ? 'Auf der Liste' : 'Meine Liste'}
          </ActionButton>
          <ActionButton col={4} className="btn btn-ghost" onClick={onOpenLanguage}>
            <Icon name="cc" w={20} />
            {language ?? 'Sprache'}
          </ActionButton>
          <ActionButton col={5} className={'btn btn-ghost' + (autosyncEnabled ? ' on' : '')} onClick={onToggleAutosync}>
            <Icon name="download" w={20} />
            {autosyncEnabled ? 'Sync aktiv' : 'Auto-Sync'}
          </ActionButton>
        </div>
      </div>
    </div>
  )
}
