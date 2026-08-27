import { useMemo, useRef, useState, type CSSProperties } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getWatchlistEnriched } from '../api/watchlist'
import { PosterCard } from '../components/common/PosterCard'
import { goToDetail } from '../navigation/detailLink'
import { useCellFocus, useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useGridColumns } from '../tv/useGridColumns'
import { chunk } from '../tv/gridColumns'

type SortMode = 'recent' | 'new' | 'az'
const SORTS: { id: SortMode; label: string }[] = [
  { id: 'recent', label: 'Zuletzt angeschaut' },
  { id: 'new', label: 'Neue Folgen' },
  { id: 'az', label: 'A–Z' },
]

function WatchlistCard({
  item,
  rowIndex,
  col,
}: {
  item: { url: string; title: string; poster_url?: string; new_content: boolean }
  rowIndex: number
  col: number
}) {
  const navigate = useNavigate()
  const { isFocused, onHover } = useCellFocus(rowIndex, col)
  return (
    <PosterCard
      title={item.title}
      posterUrl={item.poster_url}
      badge={item.new_content ? 'Neu' : undefined}
      focused={isFocused}
      onHover={onHover}
      onClick={() => goToDetail(navigate, item.url, item.title, item.poster_url)}
    />
  )
}

export function WatchlistPage() {
  const navigate = useNavigate()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const COLS = useGridColumns()
  const [sort, setSort] = useState<SortMode>('recent')
  const { data } = useQuery({ queryKey: ['watchlist-enriched'], queryFn: getWatchlistEnriched })

  const sorted = useMemo(() => {
    const items = [...(data ?? [])]
    if (sort === 'az') return items.sort((a, b) => a.title.localeCompare(b.title))
    if (sort === 'recent') return items.sort((a, b) => (b.last_watched_at ?? '').localeCompare(a.last_watched_at ?? ''))
    return items.sort((a, b) => Number(b.new_content) - Number(a.new_content))
  }, [data, sort])
  const rows = useMemo(() => chunk(sorted, COLS), [sorted, COLS])

  useRegisterNav(
    [SORTS.length, ...rows.map((r) => r.length)],
    (row, col) => {
      if (row === 0) {
        setSort(SORTS[col].id)
        setFocus({ region: 'content', row: 0, col })
        return
      }
      const item = rows[row - 1]?.[col]
      if (item) goToDetail(navigate, item.url, item.title, item.poster_url)
    },
    [sort, sorted.length, COLS],
  )

  useAutoScrollRow(scrollerRef)

  return (
    <div className="scroller" ref={scrollerRef} style={{ '--grid-cols': COLS } as CSSProperties}>
      <div className="grid-head">
        <div className="grid-eyebrow">MEINE LISTE</div>
        <h1 className="grid-h1">Watchlist</h1>
        <div className="grid-sub">{sorted.length} Titel</div>
      </div>
      <div className="filters row-anchor" data-row="0">
        {SORTS.map((s, i) => {
          const f = focus.region === 'content' && focus.row === 0 && focus.col === i
          return (
            <button
              key={s.id}
              type="button"
              className={'filter' + (sort === s.id ? ' on' : '') + (f ? ' is-foc' : '')}
              onMouseEnter={(e) => setFocus({ region: 'content', row: 0, col: i }, e)}
              onClick={() => setSort(s.id)}
            >
              {s.label}
            </button>
          )
        })}
      </div>
      {rows.map((row, ri) => (
        <div className="grid row-anchor" data-row={ri + 1} key={ri}>
          {row.map((item, ci) => (
            <WatchlistCard key={item.url} item={item} rowIndex={ri + 1} col={ci} />
          ))}
        </div>
      ))}
      <div style={{ height: 40 }} />
    </div>
  )
}
