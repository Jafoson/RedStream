import { useEffect, useState } from 'react'
import './PosterCard.css'

// Ported from the Claude Design project's data.jsx (P) — byte-for-byte the
// same palette already ported earlier from app/lib/widgets/rs_poster.dart.
const PLACEHOLDER_GRADIENTS: [string, string, number][] = [
  ['#341812', '#b15a3c', 135], // crimson
  ['#2e1206', '#c2651f', 140], // ember
  ['#271629', '#7a4f74', 135], // plum
  ['#211a2a', '#5a4a6e', 140], // indigo
  ['#142420', '#3f7e6e', 135], // teal
  ['#221d18', '#6a5f4f', 140], // steel
  ['#2e1820', '#ab6a70', 135], // rose
  ['#1b2417', '#5e7544', 140], // forest
  ['#201a24', '#534a66', 135], // midnight
  ['#2f2206', '#c8932f', 140], // gold
]

function hexA(hex: string, a: number) {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`
}

function artStyle(title: string): React.CSSProperties {
  const letter = title.trim().charAt(0).toUpperCase()
  const [a, b, ang] = PLACEHOLDER_GRADIENTS[letter ? letter.charCodeAt(0) % PLACEHOLDER_GRADIENTS.length : 0]
  return {
    backgroundImage: `radial-gradient(130% 90% at 78% 8%, ${hexA(b, 0.55)}, transparent 55%), linear-gradient(${ang}deg, ${a} 0%, ${b} 120%)`,
    backgroundColor: a,
  }
}

export interface PosterCardProps {
  title: string
  subtitle?: string
  posterUrl?: string | null
  kind?: 'anime' | 'series' | 'movie'
  badge?: string
  progress?: number // 0-1, renders a bottom progress bar when set
  focused: boolean
  onClick?: () => void
  onHover?: (e: { clientX: number; clientY: number }) => void
}

export function PosterCard({
  title,
  subtitle,
  posterUrl,
  kind,
  badge,
  progress,
  focused,
  onClick,
  onHover,
}: PosterCardProps) {
  // posterUrl being set doesn't guarantee the image actually loads — the
  // proxy-image endpoint 502s on a failed remote fetch, and TMDB simply
  // doesn't have art for some titles — so a truthy URL alone isn't enough to
  // decide "show the real image"; without this, a failed <img> load left a
  // browser broken-image icon instead of falling back to the gradient
  // placeholder every other no-poster case already gets. Reset on every
  // posterUrl change (not just once) — the same PosterCard instance can go
  // from no-poster to a lazily-backfilled TMDB poster to (in principle) a
  // different URL again without ever unmounting, so a stale "failed" from an
  // earlier URL must not stick to a later, different one.
  const [imgFailed, setImgFailed] = useState(false)
  useEffect(() => setImgFailed(false), [posterUrl])
  const showImage = !!posterUrl && !imgFailed
  return (
    <button
      type="button"
      className={'poster' + (focused ? ' is-foc' : '')}
      onClick={onClick}
      onMouseEnter={onHover}
    >
      {showImage ? (
        <img
          className="poster-art poster-art--img"
          src={posterUrl}
          alt=""
          loading="lazy"
          onError={() => setImgFailed(true)}
        />
      ) : (
        <div className="poster-art" style={artStyle(title)} />
      )}
      <div className="poster-grain" />
      <div className="poster-wm">{title[0]}</div>
      <div className="poster-shade" />
      {kind === 'anime' && <div className="poster-kind anime">ANIME</div>}
      {badge && (
        <div className="poster-top" style={{ justifyContent: 'flex-end' }}>
          <div className="poster-rating">{badge}</div>
        </div>
      )}
      <div className="poster-info">
        <div className="poster-name">{title}</div>
        {subtitle && <div className="poster-sub">{subtitle}</div>}
        {progress !== undefined && (
          <div className="cw-bar" style={{ marginTop: 8 }}>
            <i style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
        )}
      </div>
    </button>
  )
}

// Re-exported so other TV components can draw the same placeholder art for
// non-poster surfaces (continue-watching cards, episode thumbs, hero, ...).
export { artStyle as posterArtStyle }
