import { useEffect, useState } from 'react'
import { Icon } from '../layout/icons'
import { posterArtStyle } from './PosterCard'
import './ContinueWatchingCard.css'

export interface ContinueWatchingCardProps {
  title: string
  episodeLabel: string
  left?: string
  thumbnailUrl?: string | null
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
  progress,
  focused,
  onClick,
  onHover,
}: ContinueWatchingCardProps) {
  // Same reasoning as PosterCard: a truthy thumbnailUrl doesn't guarantee the
  // image actually loads (episode-preview files can be missing/mid-
  // generation), so a failed load needs to fall back to the gradient
  // placeholder instead of a broken-image icon.
  const [imgFailed, setImgFailed] = useState(false)
  useEffect(() => setImgFailed(false), [thumbnailUrl])
  const showImage = !!thumbnailUrl && !imgFailed
  return (
    <button type="button" className={'cw' + (focused ? ' is-foc' : '')} onClick={onClick} onMouseEnter={onHover}>
      {showImage ? (
        <img
          className="poster-art poster-art--img"
          src={thumbnailUrl}
          alt=""
          loading="lazy"
          onError={() => setImgFailed(true)}
        />
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
