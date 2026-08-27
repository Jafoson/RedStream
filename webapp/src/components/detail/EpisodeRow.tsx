import type { Episode } from '../../api/series'
import type { ProgressEntry } from '../../api/stream'
import { posterArtStyle } from '../common/PosterCard'
import { useFallbackImage } from '../common/useFallbackImage'
import { Icon } from '../layout/icons'
import { useCellFocus } from '../../tv/FocusEngine'

export interface EpisodeRowProps {
  episode: Episode
  progress: ProgressEntry | null
  rowIndex: number
  /** True for the one episode right after a just-finished frontier episode —
   * i.e. "up next" in the Netflix sense, even though it has no progress of
   * its own yet. */
  isNextUp?: boolean
  // Series' own horizontal/landscape backdrop — falls back to this when the
  // episode has no preview image of its own yet (only generated the first
  // time an episode is actually played, so most downloaded-but-unwatched
  // episodes have none).
  seriesBackdropUrl?: string | null
  onClick: () => void
}

export function EpisodeRow({ episode, progress, rowIndex, isNextUp, seriesBackdropUrl, onClick }: EpisodeRowProps) {
  const { isFocused, onHover } = useCellFocus(rowIndex, 0)
  const ratio = progress && progress.duration_seconds > 0 ? progress.position_seconds / progress.duration_seconds : 0
  const watched = !!progress?.completed
  const inProgress = ratio > 0 && !watched
  const title = episode.title_de || episode.title_en || `Episode ${episode.episode_number}`
  const { src: imgSrc, onError } = useFallbackImage([episode.preview_url, seriesBackdropUrl])

  return (
    <div
      className={'eprow row-anchor' + (isFocused ? ' is-foc' : '') + (isNextUp ? ' eprow--next' : '')}
      data-row={rowIndex}
      onMouseEnter={onHover}
      onClick={onClick}
    >
      <div className="ep-thumb">
        {imgSrc ? (
          <img className="poster-art poster-art--img" src={imgSrc} alt="" loading="lazy" onError={onError} />
        ) : (
          <div className="poster-art" style={posterArtStyle(title)} />
        )}
        <div className="poster-grain" />
        <div className="ep-num">F{episode.episode_number}</div>
        {inProgress && (
          <div className="cw-bar" style={{ position: 'absolute', left: 0, right: 0, bottom: 0, borderRadius: 0 }}>
            <i style={{ width: `${ratio * 100}%` }} />
          </div>
        )}
      </div>
      <div className="ep-body">
        <div className="ep-title">
          {episode.episode_number}. {title}
          {isNextUp && <span className="ep-next-badge">Weiter</span>}
        </div>
        <div className="ep-desc">
          {episode.absolute_episode_number != null && `Episode ${episode.absolute_episode_number} gesamt · `}
          {episode.available_languages.join(' · ')}
          {watched && ' · Gesehen'}
          {inProgress && ' · Wird angeschaut'}
          {episode.downloaded && !watched && !inProgress && ' · Heruntergeladen'}
        </div>
      </div>
      <div className="ep-play">
        <Icon name={watched ? 'check' : 'play'} w={20} />
      </div>
    </div>
  )
}
