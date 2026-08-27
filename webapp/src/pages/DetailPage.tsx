import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { getSeriesDetail, getSeasons, getEpisodes, getPreferredLanguage, getSeriesLanguage, setSeriesLanguage, clearSeriesLanguage } from '../api/series'
import { getAllProgress, getStreamUrl } from '../api/stream'
import { isInWatchlist, addToWatchlist, removeFromWatchlist } from '../api/watchlist'
import { checkAutosync, addAutosync, removeAutosync } from '../api/autosync'
import { findDownloadedFolder, getLibrary } from '../api/library'
import { enqueueDownload } from '../api/queue'
import { HeroSection } from '../components/detail/HeroSection'
import { SeasonTabs } from '../components/detail/SeasonTabs'
import { EpisodeRow } from '../components/detail/EpisodeRow'
import { LanguageDialog } from '../components/detail/LanguageDialog'
import type { DownloadPlayState, NextEpisodeRef } from '../navigation/playerState'
import { claimNavigation, releaseNavigation } from '../navigation/navigationGuard'
import type { Episode } from '../api/series'
import { useBackHandler, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useToast } from '../tv/ToastContext'
import './DetailPage.css'

const DEFAULT_PROVIDER = 'VOE'

export function DetailPage() {
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const toast = useToast()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const seriesUrl = params.get('url') ?? ''

  const [seasonIndex, setSeasonIndex] = useState(0)
  const [showLanguageDialog, setShowLanguageDialog] = useState(false)

  useBackHandler(() => navigate(-1))

  const detail = useQuery({ queryKey: ['series', seriesUrl], queryFn: () => getSeriesDetail(seriesUrl) })
  const seasons = useQuery({ queryKey: ['seasons', seriesUrl], queryFn: () => getSeasons(seriesUrl) })
  // Polled (not just fetch-on-mount) so the episode list's watched/in-progress/
  // next-up state and the Play button's resume label stay live while this
  // page is open — e.g. after backing out of the player mid-episode, or if
  // the same series is being watched from another tab/device.
  const progress = useQuery({
    queryKey: ['progress', 'all-for-series', seriesUrl],
    queryFn: () => getAllProgress({ limit: 500 }),
    refetchInterval: 5000,
  })
  const inWatchlist = useQuery({ queryKey: ['watchlist-check', seriesUrl], queryFn: () => isInWatchlist(seriesUrl) })
  const autosyncJob = useQuery({ queryKey: ['autosync-check', seriesUrl], queryFn: () => checkAutosync(seriesUrl) })
  const seriesLanguage = useQuery({ queryKey: ['series-language', seriesUrl], queryFn: () => getSeriesLanguage(seriesUrl) })
  const preferredLanguage = useQuery({
    queryKey: ['preferred-language', seriesUrl],
    queryFn: () => getPreferredLanguage(seriesUrl),
  })

  const activeSeason = seasons.data?.[seasonIndex]
  const episodes = useQuery({
    queryKey: ['episodes', activeSeason?.url],
    queryFn: () => getEpisodes(activeSeason!.url),
    enabled: !!activeSeason,
  })

  const seriesProgress = useMemo(
    () => (progress.data ?? []).filter((p) => p.series_url === seriesUrl),
    [progress.data, seriesUrl],
  )
  const progressByEpisode = useMemo(() => {
    const map = new Map<string, (typeof seriesProgress)[number]>()
    for (const p of seriesProgress) map.set(p.episode_url, p)
    return map
  }, [seriesProgress])

  // Port of detail_screen.dart's _computeResume(): the "frontier" is the
  // episode with the highest (season, episode_number) among any touched
  // progress rows — re-watching an earlier episode never moves it backwards,
  // matching Netflix's continue-watching semantics (the furthest point you
  // reached stays "current" regardless of what you rewatch afterward). If
  // the frontier episode was fully completed, the resume target becomes the
  // *next* episode rather than replaying the finished one.
  const frontier = useMemo(() => {
    if (seriesProgress.length === 0) return null
    return [...seriesProgress].sort((a, b) => b.season - a.season || b.episode_number - a.episode_number)[0]
  }, [seriesProgress])
  const resumeIsNextEp = !!frontier?.completed

  // Jump to the season containing the frontier on first load (mirrors
  // Flutter's initialSeason logic) — runs once, after both seasons and
  // progress have resolved, so it doesn't fight the user's own season-tab
  // clicks afterward.
  const [initialSeasonReady, setInitialSeasonReady] = useState(false)
  useEffect(() => {
    if (initialSeasonReady) return
    if (!seasons.data || progress.data === undefined) return
    if (frontier) {
      const idx = seasons.data.findIndex((s) => s.season_number === frontier.season)
      if (idx >= 0) setSeasonIndex(idx)
    }
    setInitialSeasonReady(true)
  }, [seasons.data, progress.data, frontier, initialSeasonReady])

  const language = seriesLanguage.data ?? null
  const effectiveLanguage = language ?? preferredLanguage.data ?? 'German Dub'
  const hasSeasons = (seasons.data?.length ?? 0) > 0
  const episodeRowBase = hasSeasons ? 2 : 1

  function findNextEpisode(list: Episode[] | undefined, current: Episode): NextEpisodeRef | null {
    if (!list) return null
    const idx = list.findIndex((e) => e.url === current.url)
    const next = idx >= 0 ? list[idx + 1] : undefined
    if (!next) return null
    return {
      episodeUrl: next.url,
      season: activeSeason!.season_number,
      episodeNumber: next.episode_number,
      episodeTitle: next.title_de || next.title_en,
      absoluteEpisodeNumber: next.absolute_episode_number,
    }
  }

  // Port of detail_screen.dart's _ensureInWatchlist(): pressing Play silently
  // adds the series to the Watchlist (+ enables autosync) even if the user
  // never touched the explicit watchlist button — matches the Flutter app.
  function ensureInWatchlist() {
    if (!detail.data || inWatchlist.data) return
    addToWatchlist(seriesUrl, detail.data.title, detail.data.poster_url)
      .then(() => queryClient.invalidateQueries({ queryKey: ['watchlist-check', seriesUrl] }))
      .catch(() => {})
    if (!autosyncJob.data) {
      addAutosync({
        title: detail.data.title,
        series_url: seriesUrl,
        language: effectiveLanguage,
        provider: DEFAULT_PROVIDER,
      })
        .then(() => queryClient.invalidateQueries({ queryKey: ['autosync-check', seriesUrl] }))
        .catch(() => {})
    }
  }

  function playEpisode(episode: Episode, nextEpisode: NextEpisodeRef | null, seasonNumber?: number) {
    if (!detail.data) return
    // Guards against a repeat click/Enter starting a second, independent
    // playback flow before this one has even navigated away yet.
    if (!claimNavigation()) return
    ensureInWatchlist()
    const state: DownloadPlayState = {
      episodeUrl: episode.url,
      seriesTitle: detail.data.title,
      seriesUrl,
      season: seasonNumber ?? activeSeason?.season_number ?? 1,
      episodeNumber: episode.episode_number,
      episodeTitle: episode.title_de || episode.title_en,
      absoluteEpisodeNumber: episode.absolute_episode_number,
      language: effectiveLanguage,
      provider: DEFAULT_PROVIDER,
      nextEpisode,
    }
    navigate('/download-play', { state })
    releaseNavigation()
  }

  function handlePlay() {
    if (frontier && !resumeIsNextEp) {
      // Mid-episode resume. Next-episode prefetch only resolves if the
      // resume target happens to be in the currently active season tab's
      // already-loaded episode list; otherwise playback still starts
      // correctly, it just skips prefetch/auto-advance for that one episode
      // (graceful degradation, not a bug).
      const list = episodes.data
      const current = list?.find((e) => e.episode_number === frontier.episode_number)
      playEpisode(
        current ?? {
          url: frontier.episode_url,
          episode_number: frontier.episode_number,
          title_de: frontier.episode_title ?? '',
          title_en: '',
          downloaded: false,
          available_languages: [],
          folder: null,
          absolute_episode_number: null,
        },
        current ? findNextEpisode(list, current) : null,
        frontier.season,
      )
      return
    }
    if (frontier && resumeIsNextEp) {
      // Frontier episode was finished — Netflix-style, continue with the
      // next one in the same season (matches Flutter's _playFromResume,
      // which likewise doesn't roll over into the next season here).
      const list = episodes.data
      const next = list?.find((e) => e.episode_number === frontier.episode_number + 1)
      if (next) {
        playEpisode(next, findNextEpisode(list, next), frontier.season)
        return
      }
      // Season finale with nothing to advance to in the loaded list — fall
      // through to the series-start default below.
    }
    const first = episodes.data?.[0]
    if (first) playEpisode(first, findNextEpisode(episodes.data, first))
  }

  function handleRestart() {
    const first = episodes.data?.[0]
    if (first) playEpisode(first, findNextEpisode(episodes.data, first))
  }

  function toggleWatchlist() {
    if (!detail.data) return
    const adding = !inWatchlist.data
    const action = adding
      ? addToWatchlist(seriesUrl, detail.data.title, detail.data.poster_url)
      : removeFromWatchlist(seriesUrl)
    action.then(() => {
      queryClient.invalidateQueries({ queryKey: ['watchlist-check', seriesUrl] })
      toast(adding ? 'Zur Liste hinzugefügt' : 'Von der Liste entfernt')
    })
  }

  function toggleAutosync() {
    if (!detail.data) return
    const enabling = !autosyncJob.data
    const action = enabling
      ? addAutosync({
          title: detail.data.title,
          series_url: seriesUrl,
          language: effectiveLanguage,
          provider: DEFAULT_PROVIDER,
        })
      : removeAutosync(autosyncJob.data!.id)
    action.then(() => {
      queryClient.invalidateQueries({ queryKey: ['autosync-check', seriesUrl] })
      toast(enabling ? 'Automatisch aktualisieren aktiviert' : 'Automatisch aktualisieren deaktiviert')
    })
  }

  useRegisterNav(
    [6, ...(hasSeasons ? [seasons.data!.length] : []), ...(episodes.data?.map(() => 1) ?? [])],
    (row, col) => {
      if (row === 0) {
        if (col === 0) navigate(-1)
        else if (col === 1) handlePlay()
        else if (col === 2) handleRestart()
        else if (col === 3) toggleWatchlist()
        else if (col === 4) setShowLanguageDialog(true)
        else if (col === 5) toggleAutosync()
        return
      }
      if (hasSeasons && row === 1) {
        setSeasonIndex(col)
        return
      }
      const episode = episodes.data?.[row - episodeRowBase]
      if (episode) playEpisode(episode, findNextEpisode(episodes.data, episode))
    },
    [seriesUrl, hasSeasons, seasons.data?.length, episodes.data?.length, frontier?.episode_url],
  )

  useAutoScrollRow(scrollerRef)

  // Port of detail_screen.dart's _prefetchFirstEpisode(): merely opening a
  // series' detail page (no Play tap needed) silently checks whether the
  // first episode of the *initial* season — season 1 for a fresh series, or
  // the frontier season once initialSeasonReady has resolved it, matching
  // Flutter's own `_loadEpisodes(_seasons[initialSeason], prefetch: true)` —
  // is already downloaded, and if not, queues it as a background prefetch
  // download (priority 1). Gated on initialSeasonReady rather than a
  // hardcoded season index 0, since the auto season-select above can move
  // seasonIndex away from 0 before this effect would otherwise notice.
  // Runs once per page visit.
  const prefetchedRef = useRef(false)
  useEffect(() => {
    if (prefetchedRef.current) return
    if (!initialSeasonReady || !detail.data || !activeSeason) return
    const first = episodes.data?.[0]
    if (!first) return
    prefetchedRef.current = true

    const seasonNumber = activeSeason.season_number
    ;(async () => {
      try {
        const library = await getLibrary()
        const folder = findDownloadedFolder(library, detail.data!.title, seasonNumber, first.episode_number)
        if (folder) {
          try {
            await getStreamUrl({ folder, season: seasonNumber, episode: first.episode_number })
            return // already downloaded
          } catch {
            // fall through to enqueue
          }
        }
      } catch {
        // fall through to enqueue
      }
      try {
        const preferred = await getPreferredLanguage(seriesUrl)
        const lang = first.available_languages.includes(preferred)
          ? preferred
          : first.available_languages[0] ?? preferred
        await enqueueDownload({
          title: detail.data!.title,
          series_url: seriesUrl,
          episodes: [first.url],
          language: lang,
          provider: DEFAULT_PROVIDER,
          priority: 1, // prefetch: background download while browsing detail page
        })
      } catch {
        // best-effort
      }
    })()
  }, [initialSeasonReady, detail.data, activeSeason, episodes.data, seriesUrl])

  if (!seriesUrl) {
    navigate('/', { replace: true })
    return null
  }

  if (!detail.data) {
    return (
      <div className="app-loading">
        <div className="spinner" />
      </div>
    )
  }

  return (
    <div className="scroller" ref={scrollerRef}>
      <HeroSection
        detail={detail.data}
        onBack={() => navigate(-1)}
        playLabel={
          !frontier
            ? 'Abspielen'
            : resumeIsNextEp
              ? `Weiterschauen S${frontier.season} E${frontier.episode_number + 1}`
              : `Fortsetzen S${frontier.season} E${frontier.episode_number}`
        }
        onPlay={handlePlay}
        onRestart={handleRestart}
        inWatchlist={!!inWatchlist.data}
        onToggleWatchlist={toggleWatchlist}
        language={language}
        onOpenLanguage={() => setShowLanguageDialog(true)}
        autosyncEnabled={!!autosyncJob.data?.enabled}
        onToggleAutosync={toggleAutosync}
      />

      {hasSeasons && (
        <SeasonTabs
          seasons={seasons.data!}
          active={seasonIndex}
          onSelect={setSeasonIndex}
          currentSeasonNumber={frontier?.season}
        />
      )}

      <div className="section-head" style={{ marginTop: 30, marginBottom: 6 }}>
        <div className="section-title">
          <span className="bar" />
          Folgen
        </div>
      </div>
      <div className="eplist">
        {episodes.data?.map((episode, i) => (
          <EpisodeRow
            key={episode.url}
            episode={episode}
            progress={progressByEpisode.get(episode.url) ?? null}
            rowIndex={episodeRowBase + i}
            isNextUp={
              !!frontier &&
              resumeIsNextEp &&
              activeSeason?.season_number === frontier.season &&
              episode.episode_number === frontier.episode_number + 1
            }
            onClick={() => playEpisode(episode, findNextEpisode(episodes.data, episode))}
          />
        ))}
      </div>
      <div style={{ height: 40 }} />

      {showLanguageDialog && (
        <LanguageDialog
          current={language}
          onSelect={(lang) => {
            setSeriesLanguage(seriesUrl, lang).then(() => {
              queryClient.invalidateQueries({ queryKey: ['series-language', seriesUrl] })
              setShowLanguageDialog(false)
              toast(`Sprache: ${lang}`)
            })
          }}
          onClear={() => {
            clearSeriesLanguage(seriesUrl).then(() => {
              queryClient.invalidateQueries({ queryKey: ['series-language', seriesUrl] })
              setShowLanguageDialog(false)
            })
          }}
          onClose={() => setShowLanguageDialog(false)}
        />
      )}
    </div>
  )
}
