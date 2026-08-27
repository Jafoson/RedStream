import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import { useNavigate } from 'react-router-dom'
import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import {
  getAllByKind,
  getNewAnimes,
  getNewSeries,
  getPopularAnimes,
  getPopularMovies,
  getPopularSeries,
  getTmdbPoster,
  type BrowseItem,
  type GridKind,
} from '../api/browse'
import { PosterCard } from '../components/common/PosterCard'
import { goToDetail } from '../navigation/detailLink'
import { useCellFocus, useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useGridColumns } from '../tv/useGridColumns'
import { chunk } from '../tv/gridColumns'
import './GridPage.css'

// Only the "Alle" catalog list ships without posters — lazily backfill one
// per card via TMDB once it scrolls into view. react-query's cache already
// gives this the "session-cached, fetch once per title" behavior for free.
function GridPosterCard({
  item,
  kind,
  rowIndex,
  col,
}: {
  item: BrowseItem
  kind: GridKind
  rowIndex: number
  col: number
}) {
  const navigate = useNavigate()
  const { isFocused, onHover } = useCellFocus(rowIndex, col)
  const needsPoster = !item.poster_url
  const tmdb = useQuery({
    queryKey: ['tmdb-poster', item.title],
    queryFn: () => getTmdbPoster(item.title),
    enabled: needsPoster,
    staleTime: Infinity,
  })
  return (
    <PosterCard
      title={item.title}
      posterUrl={item.poster_url || tmdb.data}
      kind={kind === 'anime' ? 'anime' : kind === 'movies' ? 'movie' : 'series'}
      focused={isFocused}
      onHover={onHover}
      onClick={() => goToDetail(navigate, item.url, item.title, item.poster_url)}
    />
  )
}

const KIND_LABEL: Record<GridKind, string> = { series: 'Serien', anime: 'Anime', movies: 'Filme' }
const KIND_EYEBROW: Record<GridKind, string> = { series: 'SERIEN-KATALOG', anime: 'ANIME-KATALOG', movies: 'FILM-KATALOG' }
const NEW_FETCHER: Partial<Record<GridKind, () => Promise<BrowseItem[]>>> = {
  anime: getNewAnimes,
  series: getNewSeries,
}
const POPULAR_FETCHER: Record<GridKind, () => Promise<BrowseItem[]>> = {
  anime: getPopularAnimes,
  series: getPopularSeries,
  movies: getPopularMovies,
}
type SortMode = 'all' | 'new' | 'trending'

function letterOf(title: string): string {
  const c = title.trim().charAt(0).toUpperCase()
  return /[A-Z]/.test(c) ? c : '#'
}

export interface GridPageProps {
  kind: GridKind
}

export function GridPage({ kind }: GridPageProps) {
  const navigate = useNavigate()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const COLS = useGridColumns()
  const [sort, setSort] = useState<SortMode>('all')
  const [genre, setGenre] = useState<string>('')
  const sentinelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    setSort('all')
    setGenre('')
  }, [kind])

  const allQuery = useInfiniteQuery({
    queryKey: ['grid', kind, genre],
    queryFn: ({ pageParam }) => getAllByKind(kind, pageParam, genre || undefined),
    initialPageParam: 1,
    getNextPageParam: (last) => (last.has_more ? last.page + 1 : undefined),
    enabled: sort === 'all',
  })

  const newQuery = useQuery({
    queryKey: ['browse-new', kind],
    queryFn: () => NEW_FETCHER[kind]?.() ?? Promise.resolve([]),
    enabled: sort === 'new' && !!NEW_FETCHER[kind],
  })

  const trendingQuery = useQuery({
    queryKey: ['browse-popular', kind],
    queryFn: () => POPULAR_FETCHER[kind](),
    enabled: sort === 'trending',
  })

  useEffect(() => {
    const el = sentinelRef.current
    if (!el || sort !== 'all') return
    const observer = new IntersectionObserver((entries) => {
      if (entries[0]?.isIntersecting && allQuery.hasNextPage && !allQuery.isFetchingNextPage) {
        allQuery.fetchNextPage()
      }
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [sort, allQuery])

  const allItems = useMemo(() => allQuery.data?.pages.flatMap((p) => p.results) ?? [], [allQuery.data])
  const allGenres = allQuery.data?.pages[0]?.all_genres ?? []

  const items = sort === 'all' ? allItems : sort === 'new' ? newQuery.data ?? [] : trendingQuery.data ?? []
  const rows = useMemo(() => chunk(items, COLS), [items, COLS])

  const sortTabs = ['all', ...(NEW_FETCHER[kind] ? ['new'] : []), 'trending'] as SortMode[]
  const genreChips = sort === 'all' ? ['', ...allGenres] : []

  useRegisterNav(
    [sortTabs.length, ...(genreChips.length ? [genreChips.length] : []), ...rows.map((r) => r.length)],
    (row, col) => {
      if (row === 0) {
        setSort(sortTabs[col])
        setFocus({ region: 'content', row: 0, col })
        return
      }
      const genreRow = genreChips.length ? 1 : -1
      if (row === genreRow) {
        setGenre(genreChips[col])
        setFocus({ region: 'content', row, col })
        return
      }
      const gridRowStart = genreChips.length ? 2 : 1
      const item = rows[row - gridRowStart]?.[col]
      if (item) goToDetail(navigate, item.url, item.title, item.poster_url)
    },
    [kind, sort, genre, items.length, COLS],
  )

  useAutoScrollRow(scrollerRef)

  const gridRowStart = genreChips.length ? 2 : 1
  let lastLetter = ''

  return (
    <div className="scroller grid-page" ref={scrollerRef} style={{ '--grid-cols': COLS } as CSSProperties}>
      <div className="grid-head">
        <div className="grid-eyebrow">{KIND_EYEBROW[kind]}</div>
        <h1 className="grid-h1">Alle {KIND_LABEL[kind]}</h1>
        <div className="grid-sub">{items.length} Titel</div>
      </div>

      <div className="filters row-anchor" data-row="0">
        {(['all', 'new', 'trending'] as SortMode[])
          .filter((m) => sortTabs.includes(m))
          .map((m, i) => {
            const label = m === 'all' ? 'Alle' : m === 'new' ? 'Neu' : 'Trend'
            const f = focus.region === 'content' && focus.row === 0 && focus.col === i
            return (
              <button
                key={m}
                type="button"
                className={'filter' + (sort === m ? ' on' : '') + (f ? ' is-foc' : '')}
                onMouseEnter={(e) => setFocus({ region: 'content', row: 0, col: i }, e)}
                onClick={() => setSort(m)}
              >
                {label}
              </button>
            )
          })}
      </div>

      {genreChips.length > 0 && (
        <div className="filters row-anchor" data-row="1">
          {genreChips.map((g, i) => {
            const f = focus.region === 'content' && focus.row === 1 && focus.col === i
            return (
              <button
                key={g || 'all-genres'}
                type="button"
                className={'filter' + (genre === g ? ' on' : '') + (f ? ' is-foc' : '')}
                onMouseEnter={(e) => setFocus({ region: 'content', row: 1, col: i }, e)}
                onClick={() => setGenre(g)}
              >
                {g || 'Alle Genres'}
              </button>
            )
          })}
        </div>
      )}

      {rows.map((row, ri) => {
        const showLetter = sort === 'all' && letterOf(row[0].title) !== lastLetter
        if (showLetter) lastLetter = letterOf(row[0].title)
        return (
          <div key={ri}>
            {showLetter && <div className="grid-letter">{lastLetter}</div>}
            <div className="grid row-anchor" data-row={gridRowStart + ri}>
              {row.map((item, ci) => (
                <GridPosterCard key={item.url} item={item} kind={kind} rowIndex={gridRowStart + ri} col={ci} />
              ))}
            </div>
          </div>
        )
      })}
      {sort === 'all' && <div ref={sentinelRef} style={{ height: 1 }} />}
      <div style={{ height: 40 }} />
    </div>
  )
}
