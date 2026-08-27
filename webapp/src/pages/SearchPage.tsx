import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { search, type SearchResult, type SearchSite } from '../api/search'
import { getPopularAnimes } from '../api/browse'
import { PosterCard } from '../components/common/PosterCard'
import { goToDetail } from '../navigation/detailLink'
import { useCellFocus, useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useGridColumns } from '../tv/useGridColumns'
import { chunk } from '../tv/gridColumns'
import { Icon } from '../components/layout/icons'
import './SearchPage.css'

type Category = 'all' | 'series' | 'anime' | 'movies'
const CATEGORIES: { id: Category; label: string }[] = [
  { id: 'all', label: 'Alle' },
  { id: 'series', label: 'Serien' },
  { id: 'anime', label: 'Anime' },
  { id: 'movies', label: 'Filme' },
]
const CATEGORY_SITE: Record<Category, SearchSite | null> = {
  all: null,
  series: 'sto',
  anime: 'aniworld',
  movies: 'megakino',
}
function dedupeByTitle(items: SearchResult[]): SearchResult[] {
  const seen = new Set<string>()
  const out: SearchResult[] = []
  for (const item of items) {
    const key = item.title.trim().toLowerCase()
    if (seen.has(key)) continue
    seen.add(key)
    out.push(item)
  }
  return out
}

function ResultCard({ item, rowIndex, col }: { item: SearchResult; rowIndex: number; col: number }) {
  const navigate = useNavigate()
  const { isFocused, onHover } = useCellFocus(rowIndex, col)
  return (
    <PosterCard
      title={item.title}
      posterUrl={item.poster_url}
      focused={isFocused}
      onHover={onHover}
      onClick={() => goToDetail(navigate, item.url, item.title, item.poster_url)}
    />
  )
}

export function SearchPage() {
  const navigate = useNavigate()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const COLS = useGridColumns()
  const [query, setQuery] = useState('')
  const [debounced, setDebounced] = useState('')
  const [category, setCategory] = useState<Category>('all')

  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 400)
    return () => clearTimeout(t)
  }, [query])

  const results = useQuery({
    queryKey: ['search', debounced, category],
    queryFn: async () => {
      const site = CATEGORY_SITE[category]
      if (site) return search(debounced, site)
      const [aniworld, sto, megakino] = await Promise.all([
        search(debounced, 'aniworld'),
        search(debounced, 'sto'),
        search(debounced, 'megakino'),
      ])
      return dedupeByTitle([...aniworld, ...sto, ...megakino])
    },
    enabled: debounced.length > 0,
  })

  const seed = useQuery({ queryKey: ['browse', 'popular-animes'], queryFn: getPopularAnimes, enabled: !debounced })
  const list = useMemo(() => (debounced ? results.data : seed.data) ?? [], [debounced, results.data, seed.data])
  const rows = useMemo(() => chunk(list, COLS), [list, COLS])

  useRegisterNav(
    [CATEGORIES.length, ...rows.map((r) => r.length)],
    (row, col) => {
      if (row === 0) {
        setCategory(CATEGORIES[col].id)
        setFocus({ region: 'content', row: 0, col })
        return
      }
      const item = rows[row - 1]?.[col]
      if (item) goToDetail(navigate, item.url, item.title, item.poster_url)
    },
    [category, list.length, COLS],
  )

  useAutoScrollRow(scrollerRef)

  // The query <input> keeps native DOM focus (autoFocus) independently of
  // the D-pad's logical row/col — otherwise Left/Right would forever move
  // the text cursor instead of navigating results, since FocusEngine
  // deliberately leaves Left/Right alone while a real text input is
  // focused (so you can still edit what you typed). Once the D-pad moves
  // past the category-pill row into the results grid, blur it so Left/Right
  // reach the grid normally.
  useEffect(() => {
    if (focus.region === 'content' && focus.row > 0) {
      inputRef.current?.blur()
    }
  }, [focus.region, focus.row])

  return (
    <div className="scroller" ref={scrollerRef} style={{ '--grid-cols': COLS } as CSSProperties}>
      <div className="search-wrap">
        <div className="filters" style={{ padding: '0 0 20px', justifyContent: 'center' }}>
          <div className="row-anchor" data-row="0" style={{ display: 'flex', gap: 11 }}>
            {CATEGORIES.map((c, i) => {
              const f = focus.region === 'content' && focus.row === 0 && focus.col === i
              return (
                <button
                  key={c.id}
                  type="button"
                  className={'filter' + (category === c.id ? ' on' : '') + (f ? ' is-foc' : '')}
                  onMouseEnter={(e) => setFocus({ region: 'content', row: 0, col: i }, e)}
                  onClick={() => setCategory(c.id)}
                >
                  {c.label}
                </button>
              )
            })}
          </div>
        </div>

        <div className="kb-query" onClick={() => inputRef.current?.focus()}>
          <Icon name="search" w={28} />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Titel oder Genre suchen"
            autoFocus
          />
        </div>
      </div>

      <div className="results-head">
        <span className="rc">{debounced ? 'Ergebnisse' : 'Beliebte Titel'}</span>
        <span className="rn">{list.length} Titel</span>
      </div>

      {debounced && list.length === 0 ? (
        <div className="search-empty">
          <Icon name="search" w={60} />
          <div className="big">Keine Treffer für „{debounced}"</div>
          <div>Versuch einen anderen Titel oder ein Genre.</div>
        </div>
      ) : (
        rows.map((row, ri) => (
          <div className="results-grid row-anchor" data-row={ri + 1} key={ri}>
            {row.map((item, ci) => (
              <ResultCard key={item.url} item={item} rowIndex={ri + 1} col={ci} />
            ))}
          </div>
        ))
      )}
      <div style={{ height: 40 }} />
    </div>
  )
}
