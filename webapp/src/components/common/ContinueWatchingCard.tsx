import { Icon } from '../layout/icons'
import { posterArtStyle } from './PosterCard'
import { useFallbackImage } from './useFallbackImage'
import './ContinueWatchingCard.css'

export interface ContinueWatchingCardProps {
  title: string
  episodeLabel: string
  left?: string
  thumbnailUrl?: string | null
  // Series' own horizontal/landscape backdrop — used when the episode has no
  // preview image of its own yet (preview.jpg is only generated the first
  // time an episode is actually *played*, so a never-watched episode's card
  // would otherwise fall straight to the generic letter/gradient
  // placeholder even though a much more contextual image is available).
  seriesBackdropUrl?: string | null
  progress: number // 0-1
  focused: boolean
  onClick?: () => void
  onHover?: (e: { clientX: number; clientY: number }) => void
}

export function ContinueWatchingCard({
  title,
  episodeLabel,
  left,
  thumbnailUrl,
  seriesBackdropUrl,
  progress,
  focused,
  onClick,
  onHover,
}: ContinueWatchingCardProps) {
  // Tries the episode's own preview first, then the series backdrop, then
  // gives up (renders the generic gradient) — a load failure (missing file,
  // still mid-generation) advances to the next candidate instead of showing
  // a broken-image icon.
  const { src: imgSrc, onError } = useFallbackImage([thumbnailUrl, seriesBackdropUrl])
  return (
    <button type="button" className={'cw' + (focused ? ' is-foc' : '')} onClick={onClick} onMouseEnter={onHover}>
      {imgSrc ? (
        <img className="poster-art poster-art--img" src={imgSrc} alt="" loading="lazy" onError={onError} />
      ) : (
        <div className="poster-art" style={posterArtStyle(title)} />
      )}
      <div className="poster-grain" />
      <div className="poster-shade" />
      {left && <div className="cw-left">{left}</div>}
      <div className="cw-play">
        <span>
          <Icon name="play" w={24} />
        </span>
      </div>
      <div className="cw-info">
        <div className="cw-name">{title}</div>
        <div className="cw-ep">{episodeLabel}</div>
        <div className="cw-bar">
          <i style={{ width: `${Math.round(progress * 100)}%` }} />
        </div>
      </div>
    </button>
  )
}
