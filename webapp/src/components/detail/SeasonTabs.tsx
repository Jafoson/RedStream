import type { Season } from '../../api/series'
import { useCellFocus } from '../../tv/FocusEngine'

export interface SeasonTabsProps {
  seasons: Season[]
  active: number
  onSelect: (index: number) => void
  /** Season number containing the continue-watching frontier, if any — shown
   * as a small dot on that pill regardless of which tab is active, so it
   * stays visible as "your current season" even after switching tabs. */
  currentSeasonNumber?: number
}

function SeasonPill({
  season,
  active,
  isCurrent,
  col,
  onSelect,
}: {
  season: Season
  active: boolean
  isCurrent: boolean
  col: number
  onSelect: () => void
}) {
  const { isFocused, onHover } = useCellFocus(1, col)
  return (
    <button
      type="button"
      className={'season-pill' + (active ? ' on' : '') + (isFocused ? ' is-foc' : '')}
      onMouseEnter={onHover}
      onClick={onSelect}
    >
      {season.are_movies ? 'Filme' : `Staffel ${season.season_number}`}
      {isCurrent && <span className="season-current-dot" title="Aktuell" />}
    </button>
  )
}

export function SeasonTabs({ seasons, active, onSelect, currentSeasonNumber }: SeasonTabsProps) {
  return (
    <div className="season-bar row-anchor" data-row="1">
      {seasons.map((season, i) => (
        <SeasonPill
          key={season.url}
          season={season}
          active={active === i}
          isCurrent={season.season_number === currentSeasonNumber}
          col={i}
          onSelect={() => onSelect(i)}
        />
      ))}
    </div>
  )
}
