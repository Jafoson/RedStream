import { useEffect, useRef, useState } from 'react'
import { useNavigate, type NavigateFunction } from 'react-router-dom'
import { useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { getAllProgress } from '../api/stream'
import { getWatchlist } from '../api/watchlist'
import { findNextEpisodeAfter } from '../api/series'
import { getNewAnimes, getNewSeries, getPopularAnimes, getPopularMovies, getPopularSeries } from '../api/browse'
import { PosterCard } from '../components/common/PosterCard'
import { ContinueWatchingCard } from '../components/common/ContinueWatchingCard'
import { Rail } from '../components/layout/Rail'
import { goToDetail } from '../navigation/detailLink'
import type { DownloadPlayState } from '../navigation/playerState'
import { claimNavigation, releaseNavigation } from '../navigation/navigationGuard'
import { useCellFocus, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import './HomePage.css'

const DEFAULT_PROVIDER = 'VOE'

type ProgressItem = Awaited<ReturnType<typeof getAllProgress>>[number]

// Shared between ContinueCell's own render-time query (what to *show*) and
// resumeContinueWatching below (what to *play*) so the two can never
// disagree — both read/write the exact same react-query cache entry.
function nextEpisodeQueryKey(p: ProgressItem) {
  return ['next-episode-after', p.series_url, p.season, p.episode_number] as const
}

// The backend's continue-watching frontier is "the furthest episode you've
// touched", full stop — it doesn't know or care whether that episode is
// already finished (>=90% watched, see PlayerPage.tsx's COMPLETED_THRESHOLD).
// Once it is, both the card's own display and what clicking it actually
// plays need to point at the *next* episode instead — otherwise the row
// keeps showing (and replaying the tail end of) something you already
// finished, right up until you touch the next one yourself elsewhere.
async function resolveContinueTarget(queryClient: QueryClient, p: ProgressItem) {
  if (!p.completed) {
    return { episodeUrl: p.episode_url, season: p.season, episodeNumber: p.episode_number, episodeTitle: p.episode_title }
  }
  const next = await queryClient.fetchQuery({
    queryKey: nextEpisodeQueryKey(p),
    queryFn: () => findNextEpisodeAfter(p.series_url, p.season, p.episode_number),
    staleTime: 5 * 60 * 1000,
  })
  if (next) {
    return { episodeUrl: next.episodeUrl, season: next.season, episodeNumber: next.episodeNumber, episodeTitle: next.episodeTitle }
  }
  // Season finale (or the lookup failed) — nothing to advance to, fall back
  // to the frontier itself rather than doing nothing on click.
  return { episodeUrl: p.episode_url, season: p.season, episodeNumber: p.episode_number, episodeTitle: p.episode_title }
}

// Continue-watching cards jump straight into playback (resuming at the saved
// position via PlayerPage's existing resume logic) rather than to the
// Detail page — unlike every other card on Home, this one already IS a
// specific episode the user chose to keep watching, so an extra stop on the
// way just gets in the way. Effectively navigates immediately: the target
// resolves from resolveContinueTarget, which is synchronous in the common
// (not-yet-completed) case and, for a completed frontier, resolves from
// react-query's cache instantly if ContinueCell's own render-time query
// already populated it (the normal case, since that query starts as soon as
// the row renders, well before a click) — either way there's no visible
// delay. Language isn't known synchronously here either way, so — same as
// before — it's left for DownloadPlayPage to resolve right after arriving.
function resumeContinueWatching(navigate: NavigateFunction, queryClient: QueryClient, p: ProgressItem) {
  // Guards against a repeat click starting a second, independent playback
  // flow before the first one's navigate() has actually taken effect.
  if (!claimNavigation()) return
  resolveContinueTarget(queryClient, p).then((target) => {
    const state: DownloadPlayState = {
      episodeUrl: target.episodeUrl,
      seriesTitle: p.series_title,
      seriesUrl: p.series_url,
      season: target.season,
      episodeNumber: target.episodeNumber,
      episodeTitle: target.episodeTitle,
      provider: DEFAULT_PROVIDER,
    }
    navigate('/download-play', { state })
    releaseNavigation()
  })
}

function greeting(hour: number): string {
  if (hour < 5) return 'Gute Nacht'
  if (hour < 11) return 'Guten Morgen'
  if (hour < 17) return 'Hallo'
  if (hour < 22) return 'Guten Abend'
  return 'Gute Nacht'
}

export function HomePage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const [now, setNow] = useState(() => new Date())

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60000)
    return () => clearInterval(t)
  }, [])

  // Polled (not just fetch-on-mount) so the "Weiterschauen" row's progress
  // bars/labels stay live while Home is open — same reasoning as
  // DetailPage.tsx's progress query — without requiring a manual reload.
  const continueWatching = useQuery({
    queryKey: ['progress', 'continue'],
    queryFn: () => getAllProgress({ continueOnly: true, limit: 50 }),
    refetchInterval: 5000,
  })
  const watchlist = useQuery({ queryKey: ['watchlist'], queryFn: getWatchlist })
  const newAnimes = useQuery({ queryKey: ['browse', 'new-animes'], queryFn: getNewAnimes })
  const popularAnimes = useQuery({ queryKey: ['browse', 'popular-animes'], queryFn: getPopularAnimes })
  const newSeries = useQuery({ queryKey: ['browse', 'new-series'], queryFn: getNewSeries })
  const popularSeries = useQuery({ queryKey: ['browse', 'popular-series'], queryFn: getPopularSeries })
  const popularMovies = useQuery({ queryKey: ['browse', 'popular-movies'], queryFn: getPopularMovies })

  // These 7 rails load from 7 independent queries that settle at different
  // times. Building `rows` from whichever ones happen to have `.data` yet
  // (the previous approach) meant a rail's row *index* would shift under the
  // user's feet as later queries resolved — if you were D-pad-navigating
  // "Neue Anime" (say row 2) the moment "Meine Liste" (row 1) finished
  // loading and got inserted before it, "Neue Anime" would silently become
  // row 3, and your still-row-2 focus would land on a different rail
  // entirely. Waiting for every query to settle before computing `rows`
  // even once means the row order is stable from the very first render.
  const allSettled = ![
    continueWatching,
    watchlist,
    newAnimes,
    popularAnimes,
    newSeries,
    popularSeries,
    popularMovies,
  ].some((q) => q.isPending)

  const rows = allSettled
    ? [
        { key: 'cw', label: 'Weiterschauen', items: continueWatching.data ?? [] },
        { key: 'wl', label: 'Meine Liste', items: watchlist.data ?? [] },
        { key: 'na', label: 'Neue Anime', items: newAnimes.data ?? [] },
        { key: 'pa', label: 'Beliebte Anime', items: popularAnimes.data ?? [] },
        { key: 'ns', label: 'Neue Serien', items: newSeries.data ?? [] },
        { key: 'ps', label: 'Beliebte Serien', items: popularSeries.data ?? [] },
        { key: 'pm', label: 'Beliebte Filme', items: popularMovies.data ?? [] },
      ].filter((r) => r.items.length > 0)
    : []

  useRegisterNav(
    rows.map((r) => r.items.length),
    (row, col) => {
      const r = rows[row]
      if (!r) return
      if (r.key === 'cw') {
        const p = continueWatching.data?.[col]
        if (p) resumeContinueWatching(navigate, queryClient, p)
      } else {
        const item = r.items[col] as { url: string; title: string; poster_url?: string }
        goToDetail(navigate, item.url, item.title, item.poster_url)
      }
    },
    [rows.map((r) => r.items.length).join(',')],
    'remember',
  )

  useAutoScrollRow(scrollerRef)

  const weekday = now.toLocaleDateString('de-DE', { weekday: 'long' })
  const day = now.toLocaleDateString('de-DE', { day: 'numeric', month: 'long' })

  if (!allSettled) {
    return (
      <div className="app-loading">
        <div className="spinner" />
      </div>
    )
  }

  return (
    <div className="scroller" ref={scrollerRef}>
      <div className="home-greet">
        <div>
          <h1>
            {greeting(now.getHours())}
          </h1>
          <p>Schnapp dir eine Decke — wo möchtest du weitermachen?</p>
        </div>
        <div className="clock">
          <b>{now.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}</b>
          {weekday}, {day}
        </div>
      </div>

      {rows.map((r, rowIndex) => (
        <Rail key={r.key} title={r.label} rowIndex={rowIndex} itemCount={r.items.length}>
          {r.key === 'cw'
            ? (r.items as Awaited<ReturnType<typeof getAllProgress>>).map((p, i) => (
                <ContinueCell key={p.episode_url} rowIndex={rowIndex} col={i} progress={p} />
              ))
            : (r.items as { url: string; title: string; poster_url?: string }[]).map((item, i) => (
                <PosterCell key={item.url} rowIndex={rowIndex} col={i} item={item} />
              ))}
        </Rail>
      ))}
    </div>
  )
}

function PosterCell({
  rowIndex,
  col,
  item,
}: {
  rowIndex: number
  col: number
  item: { url: string; title: string; poster_url?: string }
}) {
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

function ContinueCell({
  rowIndex,
  col,
  progress: p,
}: {
  rowIndex: number
  col: number
  progress: ProgressItem
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { isFocused, onHover } = useCellFocus(rowIndex, col)

  // Once the frontier episode is finished (>=90% watched — see PlayerPage's
  // COMPLETED_THRESHOLD), show the *next* episode instead of the one already
  // watched — same react-query cache entry resumeContinueWatching's
  // resolveContinueTarget reads, so what's displayed and what clicking the
  // card plays can never disagree.
  const nextQuery = useQuery({
    queryKey: nextEpisodeQueryKey(p),
    queryFn: () => findNextEpisodeAfter(p.series_url, p.season, p.episode_number),
    // !! coerces to a real boolean — despite the ProgressEntry type saying
    // `completed: boolean`, the backend actually serializes SQLite's 0/1
    // straight through as a JSON *number*, and react-query's `enabled`
    // strictly rejects anything that isn't a real boolean/callback at
    // runtime, throwing and unmounting the whole app (no error boundary
    // anywhere in this tree) rather than just misbehaving quietly.
    enabled: !!p.completed,
    staleTime: 5 * 60 * 1000,
  })

  const upNext = p.completed ? nextQuery.data : null
  const season = upNext ? upNext.season : p.season
  const episodeNumber = upNext ? upNext.episodeNumber : p.episode_number
  const ratio = upNext ? 0 : p.duration_seconds > 0 ? p.position_seconds / p.duration_seconds : 0
  const remaining =
    !upNext && p.duration_seconds > 0 ? Math.max(0, Math.round((p.duration_seconds - p.position_seconds) / 60)) : null

  return (
    <ContinueWatchingCard
      title={p.series_title}
      episodeLabel={`S${season}:E${episodeNumber}`}
      left={remaining !== null ? `${remaining} min übrig` : undefined}
      thumbnailUrl={upNext ? undefined : p.preview_url}
      progress={ratio}
      focused={isFocused}
      onHover={onHover}
      onClick={() => resumeContinueWatching(navigate, queryClient, p)}
    />
  )
}
