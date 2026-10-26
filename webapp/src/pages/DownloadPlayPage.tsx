// Port of app/lib/screens/download_play_screen.dart: resolve an already-
// downloaded episode straight to the player; otherwise stream it directly
// from the hoster (api/live.ts, unless switched off in Settings), and only if
// that isn't possible start a download and wait for it, showing ffmpeg
// progress in the meantime.
import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { findDownloadedFolder, getLibrary } from '../api/library'
import { getStreamUrl } from '../api/stream'
import { findNextEpisodeAfter, getPreferredLanguage, setSeriesLanguage } from '../api/series'
import { cancelQueueItem, enqueueDownload, findQueueItemByEpisode, getQueue, type QueueItem } from '../api/queue'
import { isDirectStreamEnabled, resolveLiveStream, type LiveKind } from '../api/live'
import { languageLabel } from '../components/player/PlayerControls'
import { clearNowPlaying, setNowPlaying, type NowPlaying } from '../cast/playback'
import type { DownloadPlayState, NextEpisodeRef, PlayerState } from '../navigation/playerState'
import './DownloadPlayPage.css'

const QUEUE_POLL_MS = 2000
const LIBRARY_POLL_MS = 3000

export function DownloadPlayPage() {
  const { state } = useLocation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const s = state as DownloadPlayState | null

  const [status, setStatus] = useState<'resolving' | 'streaming' | 'queued' | 'downloading' | 'failed'>('resolving')
  // Shown once direct streaming was tried and didn't work for this episode.
  const [streamUnavailable, setStreamUnavailable] = useState(false)
  const [percent, setPercent] = useState<number | null>(null)
  const queueIdRef = useRef<number | null>(null)
  const stoppedRef = useRef(false)
  // Which navigation state this page last started for: the page can be
  // re-entered with a new state while staying mounted (e.g. "In … weiter-
  // schauen" after a failed language switch replaces /download-play itself).
  const startedRef = useRef<DownloadPlayState | null>(null)
  // Filled in by start() below, before it's needed by either
  // tryResolveFromLibrary() or the queue-completion path — whichever of
  // language/nextEpisode the caller didn't already know synchronously.
  const resolvedRef = useRef<{ language: string; nextEpisode: NextEpisodeRef | null | undefined }>({
    language: 'German Dub',
    nextEpisode: undefined,
  })

  const goToPlayer = useCallback(
    (folder: string, streamUrl?: string, liveKind?: LiveKind) => {
      if (!s) return
      const { language, nextEpisode } = resolvedRef.current
      const playerState: PlayerState = {
        folder,
        season: s.season,
        episodeNumber: s.episodeNumber,
        episodeUrl: s.episodeUrl,
        seriesTitle: s.seriesTitle,
        seriesUrl: s.seriesUrl,
        episodeTitle: s.episodeTitle,
        absoluteEpisodeNumber: s.absoluteEpisodeNumber,
        language,
        provider: s.provider,
        customPathId: s.customPathId,
        nextEpisode,
        streamUrl,
        live: liveKind ? { kind: liveKind } : undefined,
      }
      navigate('/watch', { replace: true, state: playerState })
    },
    [s, navigate],
  )

  // Finds the folder for an already-downloaded episode WITHOUT navigating —
  // split out from tryResolveFromLibrary below so start() can run this
  // concurrently with resolving language/nextEpisode and only call
  // goToPlayer (which reads resolvedRef) once both are actually done,
  // instead of racing them.
  const findFolderInLibrary = useCallback(async (): Promise<{ folder: string; streamUrl: string } | null> => {
    if (!s) return null
    // Routed through react-query's cache (same ['library'] key LibraryPage's
    // own useQuery already populates) instead of a raw fetch every time —
    // this was the actual cause of "already-downloaded episodes take forever
    // to start," reported as much slower than the native Flutter app despite
    // hitting the identical backend: every single click here re-fetched and
    // re-parsed the *entire* library listing from scratch, even seconds
    // after DetailPage's own prefetch check had just fetched the exact same
    // data. A short staleTime is enough — this is a "does the file already
    // exist" check, not something that needs to be millisecond-fresh, and a
    // stale cache only costs a slightly-too-eager fallback to the
    // download-queue path, never incorrect playback.
    const library = await queryClient.fetchQuery({ queryKey: ['library'], queryFn: getLibrary, staleTime: 30_000 })
    const folder = findDownloadedFolder(library, s.seriesTitle, s.season, s.episodeNumber)
    if (!folder) return null
    try {
      // Fetched here purely to VERIFY the file really exists — but the
      // result is the exact same URL PlayerPage would otherwise fetch again
      // itself a moment later, so it's threaded through via goToPlayer's
      // streamUrl param instead of being thrown away, cutting a real
      // duplicate backend round-trip out of the already-downloaded fast
      // path (confirmed via a real network trace: this call and PlayerPage's
      // own were the two single biggest contributors to time-to-playable).
      const streamUrl = await getStreamUrl({
        folder,
        season: s.season,
        episode: s.episodeNumber,
        customPathId: s.customPathId,
      })
      return { folder, streamUrl }
    } catch {
      return null
    }
  }, [s, queryClient])

  // Used by the queue-completion and library-poll fallback paths, both of
  // which fire well after start()'s own resolvePromise has long since
  // finished — safe to navigate immediately here, unlike the initial
  // concurrent race in start() below.
  const tryResolveFromLibrary = useCallback(async (): Promise<boolean> => {
    const found = await findFolderInLibrary()
    if (!found) return false
    goToPlayer(found.folder, found.streamUrl)
    return true
  }, [findFolderInLibrary, goToPlayer])

  useEffect(() => {
    if (!s || startedRef.current === s) return
    startedRef.current = s
    stoppedRef.current = false
    queueIdRef.current = null
    setStatus('resolving')
    setStreamUnavailable(false)
    setPercent(null)

    let queuePoll: ReturnType<typeof setInterval> | null = null
    let libraryPoll: ReturnType<typeof setInterval> | null = null

    async function pollQueue() {
      const id = queueIdRef.current
      if (id === null) return
      const { items, ffmpeg_progress } = await getQueue()
      const item = items.find((i: QueueItem) => i.id === id)
      if (!item) return
      if (item.status === 'completed') {
        stop()
        await tryResolveFromLibrary()
      } else if (item.status === 'failed' || item.status === 'cancelled') {
        stop()
        if (!stoppedRef.current) setStatus('failed')
      } else if (item.status === 'running') {
        setStatus('downloading')
        const progress =
          ffmpeg_progress && typeof (ffmpeg_progress as { percent?: number }).percent === 'number'
            ? (ffmpeg_progress as { percent: number }).percent
            : (ffmpeg_progress as Record<string, { percent: number }>)?.[String(id)]?.percent
        if (typeof progress === 'number') setPercent(progress)
      }
    }

    function stop() {
      stoppedRef.current = true
      if (queuePoll) clearInterval(queuePoll)
      if (libraryPoll) clearInterval(libraryPoll)
    }

    async function start() {
      // Resolve whichever of language/nextEpisode the caller didn't already
      // know synchronously — deferred to here (after the click already
      // navigated) rather than before navigating, so clicking Play/next-
      // episode feels instant instead of the trigger sitting unresponsive
      // for a network round-trip with no visible feedback.
      //
      // Started here but NOT awaited yet — it runs concurrently with the
      // library check below rather than blocking it. Neither language nor
      // nextEpisode gates actually starting playback (PlayerPage only uses
      // them for background/auxiliary purposes: the next-episode prefetch
      // download and the auto-advance button), so making the already-
      // downloaded fast path wait for a language lookup plus a two-request
      // season/episode lookup *before even checking whether the file is
      // already on disk* was pure wasted latency on the single most common
      // click in the app (rewatching/continuing something already
      // downloaded) — this is what actually made playback starts feel much
      // slower than the native app hitting the same backend.
      const resolvePromise = (async () => {
        const language = s!.language ?? (await getPreferredLanguage(s!.seriesUrl).catch(() => 'German Dub'))
        const nextEpisode =
          s!.nextEpisode !== undefined
            ? s!.nextEpisode
            : await findNextEpisodeAfter(s!.seriesUrl, s!.season, s!.episodeNumber)
        resolvedRef.current = { language, nextEpisode }
      })()

      // 1. Already downloaded? Runs concurrently with resolvePromise above.
      // Both are awaited together before calling goToPlayer (which reads
      // resolvedRef) — findFolderInLibrary alone, unlike tryResolveFromLibrary,
      // doesn't navigate itself, specifically so this can't race ahead of
      // resolvePromise finishing and read a still-default resolvedRef.
      // A language switch from the player must not land on a downloaded file:
      // the library can't tell which language that file is in.
      const [, found] = await Promise.all([resolvePromise, s!.languageSwitch ? null : findFolderInLibrary()])
      if (found) {
        goToPlayer(found.folder, found.streamUrl)
        return
      }

      // 2. Not on disk: stream it straight from the hoster instead of
      // making the viewer wait for the whole episode to download.
      if (s!.forceDownload) {
        setStreamUnavailable(true)
      } else if (isDirectStreamEnabled() || s!.languageSwitch) {
        setStatus('streaming')
        try {
          const live = await resolveLiveStream({
            episodeUrl: s!.episodeUrl,
            language: resolvedRef.current.language,
            provider: s!.provider,
          })
          if (stoppedRef.current) return
          goToPlayer('', live.url, live.kind)
          return
        } catch {
          if (stoppedRef.current) return
          // Downloading instead could just as well end up playing the old
          // language from disk, so a language switch stops here.
          if (s!.languageSwitch) {
            setStatus('failed')
            return
          }
          setStreamUnavailable(true)
        }
      }

      // 3. Already queued/running from elsewhere?
      let id = await findQueueItemByEpisode(s!.episodeUrl)
      if (id === null) {
        const result = await enqueueDownload({
          title: s!.seriesTitle,
          series_url: s!.seriesUrl,
          episodes: [s!.episodeUrl],
          language: resolvedRef.current.language,
          provider: s!.provider,
          custom_path_id: s!.customPathId ?? undefined,
          priority: 0,
        })
        id = result.queue_id
      }
      queueIdRef.current = id
      setStatus('queued')

      queuePoll = setInterval(pollQueue, QUEUE_POLL_MS)
      // Fallback: the file can appear on disk even if we miss the queue's
      // 'completed' transition (matches Flutter's own belt-and-suspenders
      // library poller).
      libraryPoll = setInterval(async () => {
        if (await tryResolveFromLibrary()) stop()
      }, LIBRARY_POLL_MS)
    }

    start()
    return stop
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s])

  // Shows up as "loading" in the cast heartbeat until the player takes over.
  useEffect(() => {
    if (!s) return
    const info: NowPlaying = {
      episodeUrl: s.episodeUrl,
      seriesTitle: s.seriesTitle,
      seriesUrl: s.seriesUrl,
      season: s.season,
      episodeNumber: s.episodeNumber,
      episodeTitle: s.episodeTitle,
      language: s.language,
    }
    setNowPlaying(info, null)
    return () => clearNowPlaying(info)
  }, [s])

  async function handleCancel() {
    if (queueIdRef.current !== null) {
      try {
        await cancelQueueItem(queueIdRef.current, true)
      } catch {
        // best-effort
      }
    }
    navigate(-1)
  }

  if (!s) {
    navigate('/', { replace: true })
    return null
  }

  return (
    <div className="download-play">
      <button type="button" className="back-btn download-play__back" onClick={handleCancel}>
        Zurück
      </button>
      <div className="download-play__body">
        <h1 className="text-title-lg">{s.seriesTitle}</h1>
        <p className="text-body-md">
          S{String(s.season).padStart(2, '0')}E{String(s.episodeNumber).padStart(2, '0')}
          {s.episodeTitle ? ` — ${s.episodeTitle}` : ''}
        </p>
        {status === 'failed' ? (
          <p className="download-play__status download-play__status--error">
            {s.languageSwitch
              ? `„${languageLabel(s.language ?? '')}“ kann für diese Folge gerade nicht gestreamt werden.`
              : 'Download fehlgeschlagen'}
          </p>
        ) : (
          <>
            <div className="download-play__progress">
              <div className="download-play__progress-fill" style={{ width: `${percent ?? 0}%` }} />
            </div>
            <p className="download-play__status">
              {status === 'resolving' && 'Wird aufgelöst…'}
              {status === 'streaming' && 'Stream wird vorbereitet…'}
              {status === 'queued' && 'In der Warteschlange…'}
              {status === 'downloading' && `Lädt herunter… ${percent !== null ? `${Math.round(percent)}%` : ''}`}
            </p>
            {streamUnavailable && (
              <p className="download-play__note">Direktes Streaming ist für diese Folge nicht möglich – sie wird heruntergeladen.</p>
            )}
          </>
        )}
        {status === 'failed' && s.languageSwitch && (
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => {
              const back: DownloadPlayState = { ...s, language: s.languageSwitch!.previousLanguage, languageSwitch: undefined }
              setSeriesLanguage(s.seriesUrl, back.language!).catch(() => {})
              navigate('/download-play', { replace: true, state: back })
            }}
          >
            In „{languageLabel(s.languageSwitch.previousLanguage)}“ weiterschauen
          </button>
        )}
        {status === 'failed' && !s.languageSwitch && (
          <button type="button" className="btn btn-primary" onClick={() => navigate(-1)}>
            Zurück
          </button>
        )}
      </div>
    </div>
  )
}
