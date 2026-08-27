// Port of app/lib/screens/download_play_screen.dart: resolve an already-
// downloaded episode straight to the player, or start a download and wait
// for it, showing ffmpeg progress in the meantime.
import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { findDownloadedFolder, getLibrary } from '../api/library'
import { getStreamUrl } from '../api/stream'
import { findNextEpisodeAfter, getPreferredLanguage } from '../api/series'
import { cancelQueueItem, enqueueDownload, findQueueItemByEpisode, getQueue, type QueueItem } from '../api/queue'
import type { DownloadPlayState, NextEpisodeRef, PlayerState } from '../navigation/playerState'
import './DownloadPlayPage.css'

const QUEUE_POLL_MS = 2000
const LIBRARY_POLL_MS = 3000

export function DownloadPlayPage() {
  const { state } = useLocation()
  const navigate = useNavigate()
  const s = state as DownloadPlayState | null

  const [status, setStatus] = useState<'resolving' | 'queued' | 'downloading' | 'failed'>('resolving')
  const [percent, setPercent] = useState<number | null>(null)
  const queueIdRef = useRef<number | null>(null)
  const stoppedRef = useRef(false)
  const startedRef = useRef(false)
  // Filled in by start() below, before it's needed by either
  // tryResolveFromLibrary() or the queue-completion path — whichever of
  // language/nextEpisode the caller didn't already know synchronously.
  const resolvedRef = useRef<{ language: string; nextEpisode: NextEpisodeRef | null | undefined }>({
    language: 'German Dub',
    nextEpisode: undefined,
  })

  const goToPlayer = useCallback(
    (folder: string) => {
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
      }
      navigate('/watch', { replace: true, state: playerState })
    },
    [s, navigate],
  )

  const tryResolveFromLibrary = useCallback(async (): Promise<boolean> => {
    if (!s) return false
    const library = await getLibrary()
    const folder = findDownloadedFolder(library, s.seriesTitle, s.season, s.episodeNumber)
    if (!folder) return false
    try {
      await getStreamUrl({ folder, season: s.season, episode: s.episodeNumber, customPathId: s.customPathId })
    } catch {
      return false
    }
    goToPlayer(folder)
    return true
  }, [s, goToPlayer])

  useEffect(() => {
    if (!s || startedRef.current) return
    startedRef.current = true

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
      const language = s!.language ?? (await getPreferredLanguage(s!.seriesUrl).catch(() => 'German Dub'))
      const nextEpisode =
        s!.nextEpisode !== undefined
          ? s!.nextEpisode
          : await findNextEpisodeAfter(s!.seriesUrl, s!.season, s!.episodeNumber)
      resolvedRef.current = { language, nextEpisode }

      // 1. Already downloaded?
      if (await tryResolveFromLibrary()) return

      // 2. Already queued/running from elsewhere?
      let id = await findQueueItemByEpisode(s!.episodeUrl)
      if (id === null) {
        const result = await enqueueDownload({
          title: s!.seriesTitle,
          series_url: s!.seriesUrl,
          episodes: [s!.episodeUrl],
          language,
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
          <p className="download-play__status download-play__status--error">Download fehlgeschlagen</p>
        ) : (
          <>
            <div className="download-play__progress">
              <div className="download-play__progress-fill" style={{ width: `${percent ?? 0}%` }} />
            </div>
            <p className="download-play__status">
              {status === 'resolving' && 'Wird aufgelöst…'}
              {status === 'queued' && 'In der Warteschlange…'}
              {status === 'downloading' && `Lädt herunter… ${percent !== null ? `${Math.round(percent)}%` : ''}`}
            </p>
          </>
        )}
        {status === 'failed' && (
          <button type="button" className="btn btn-primary" onClick={() => navigate(-1)}>
            Zurück
          </button>
        )}
      </div>
    </div>
  )
}
