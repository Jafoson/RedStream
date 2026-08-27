import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { HlsPlayer } from '../components/player/HlsPlayer'
import { PlayerControls } from '../components/player/PlayerControls'
import {
  getEpisodeProgress,
  getSkipTimes,
  getThumbnails,
  saveProgress,
  streamFileFromUrl,
  getStreamUrl,
  type ProgressEntry,
  type SkipTimes,
  type ThumbnailMeta,
} from '../api/stream'
import { enqueueDownload } from '../api/queue'
import { findDownloadedFolder, getLibrary } from '../api/library'
import { authHeaders } from '../api/client'
import { AUTO_ADVANCE_THRESHOLD_S } from '../components/player/PlayerControls'
import { claimNavigation, releaseNavigation } from '../navigation/navigationGuard'
import type { DownloadPlayState, PlayerState } from '../navigation/playerState'
import './PlayerPage.css'

const PROGRESS_SAVE_INTERVAL_MS = 10000
const COMPLETED_THRESHOLD = 0.9
const RESUME_MIN_SECONDS = 30

export function PlayerPage() {
  const { state } = useLocation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const s = state as PlayerState | null

  const videoRef = useRef<HTMLVideoElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [streamUrl, setStreamUrl] = useState<string | null>(null)
  const [skipTimes, setSkipTimes] = useState<SkipTimes | null>(null)
  const [thumbnails, setThumbnails] = useState<ThumbnailMeta | null>(null)
  const resumeAppliedRef = useRef(false)
  const resumePositionRef = useRef(0)
  const lastKnownRef = useRef({ time: 0, duration: 0 })
  const nextSegmentPrefetchedRef = useRef(false)
  const nextEpisodeAdvancedRef = useRef(false)

  useEffect(() => {
    if (!s) return
    let cancelled = false
    // This effect re-runs per episode (deps below), but PlayerPage itself
    // stays mounted across an in-place episode change (same /watch route,
    // just new location.state) — without resetting these, a ref left over
    // from the *previous* episode would silently make this one skip its own
    // resume-position/next-segment-prefetch behavior.
    resumeAppliedRef.current = false
    nextSegmentPrefetchedRef.current = false
    nextEpisodeAdvancedRef.current = false

    getStreamUrl({ folder: s.folder, season: s.season, episode: s.episodeNumber, customPathId: s.customPathId }).then(
      (url) => {
        if (!cancelled) setStreamUrl(url)
      },
    )

    getSkipTimes(s.seriesTitle, s.episodeNumber)
      .then((t) => !cancelled && setSkipTimes(t))
      .catch(() => {})

    getEpisodeProgress(s.episodeUrl)
      .then((p) => {
        if (p && !p.completed && p.position_seconds > RESUME_MIN_SECONDS) {
          resumePositionRef.current = p.position_seconds
        }
      })
      .catch(() => {})

    // Prefetch the next episode as soon as this one starts, matching Flutter.
    if (s.nextEpisode) {
      enqueueDownload({
        title: s.seriesTitle,
        series_url: s.seriesUrl,
        episodes: [s.nextEpisode.episodeUrl],
        language: s.language,
        provider: s.provider,
        custom_path_id: s.customPathId ?? undefined,
        priority: 1,
      }).catch(() => {})
    }

    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s?.folder, s?.season, s?.episodeNumber])

  useEffect(() => {
    if (!streamUrl || !s) return
    const filepath = streamFileFromUrl(streamUrl)
    if (!filepath) return
    getThumbnails(filepath)
      .then((meta) => setThumbnails(meta))
      .catch(() => {})
  }, [streamUrl, s])

  // Once within AUTO_ADVANCE_THRESHOLD_S of the end (same window the "next
  // episode" card uses), silently warm the browser's HTTP cache with the
  // next episode's manifest + first segment — this is separate from the
  // priority-1 *download* enqueued above, which gets the file onto disk but
  // says nothing about it being fetched over HTTP yet. By the time
  // auto-advance actually swaps episodes, the new player's very first
  // requests are cache hits instead of a cold network round-trip, so
  // playback continues instead of visibly reloading.
  useEffect(() => {
    if (!s?.nextEpisode) return
    const video = videoRef.current
    if (!video) return
    const next = s.nextEpisode

    async function prefetchNextSegment() {
      const v = videoRef.current
      if (!v || !v.duration || nextSegmentPrefetchedRef.current) return
      if (v.duration - v.currentTime > AUTO_ADVANCE_THRESHOLD_S) return
      nextSegmentPrefetchedRef.current = true
      try {
        const library = await getLibrary()
        const folder = findDownloadedFolder(library, s!.seriesTitle, next.season, next.episodeNumber)
        if (!folder) return // not downloaded yet — nothing to warm
        const nextStreamUrl = await getStreamUrl({
          folder,
          season: next.season,
          episode: next.episodeNumber,
          customPathId: s!.customPathId,
        })
        const manifestRes = await fetch(nextStreamUrl, { headers: authHeaders() })
        const manifestText = await manifestRes.text()
        const firstSegment = manifestText
          .split('\n')
          .map((line) => line.trim())
          .find((line) => line && !line.startsWith('#'))
        if (firstSegment) {
          const segmentUrl = new URL(firstSegment, new URL(nextStreamUrl, window.location.origin)).toString()
          fetch(segmentUrl, { headers: authHeaders() }).catch(() => {})
        }
      } catch {
        // best-effort — auto-advance still works fine on a cold cache, just
        // like before this existed
      }
    }

    video.addEventListener('timeupdate', prefetchNextSegment)
    return () => video.removeEventListener('timeupdate', prefetchNextSegment)
  }, [s, videoRef])

  function handleLoadedMetadata() {
    const video = videoRef.current
    if (!video || resumeAppliedRef.current) return
    const resume = resumePositionRef.current
    if (resume > 0 && resume < video.duration - 5) {
      video.currentTime = resume
    }
    resumeAppliedRef.current = true
  }

  useEffect(() => {
    if (!s) return
    const video = videoRef.current
    let lastSaved = 0

    function persist(completed = false) {
      const { time, duration } = lastKnownRef.current
      // Nothing real to save yet (metadata hasn't loaded) — most notably true
      // for this effect's own early cleanup, which fires the moment
      // `streamUrl` first resolves from null to a real value, well before
      // any playback has happened.
      if (!s || duration <= 0) return
      const isCompleted = completed || time / duration >= COMPLETED_THRESHOLD
      const filepath = streamUrl ? streamFileFromUrl(streamUrl) : null
      saveProgress({
        episode_url: s.episodeUrl,
        series_title: s.seriesTitle,
        series_url: s.seriesUrl,
        season: s.season,
        episode_number: s.episodeNumber,
        episode_title: s.episodeTitle,
        position_seconds: time,
        duration_seconds: duration,
        completed: isCompleted,
        stream_file: filepath,
      }).catch(() => {})

      // Skipped once nextEpisodeAdvancedRef is set (by maybeAdvanceFrontier,
      // below — normally already fired well before this call, see there for
      // why) so this can't stomp the advanced cache entry back to the
      // finished episode's data on a later periodic persist() call (e.g. the
      // video keeps running into the auto-advance countdown after
      // completion).
      if (!nextEpisodeAdvancedRef.current) {
        queryClient.setQueryData<ProgressEntry[]>(['progress', 'continue'], (old) =>
          old?.map((item) =>
            item.episode_url === s.episodeUrl
              ? { ...item, position_seconds: time, duration_seconds: duration, completed: isCompleted }
              : item,
          ),
        )
      }
    }

    // Advances the continue-watching *frontier itself* in the database the
    // moment this episode crosses 90%, instead of leaving it pointing at the
    // finished episode and resolving "what's next" later, reactively, on
    // whatever page next reads it. Called from trackTime() below — i.e. on
    // EVERY 'timeupdate'/'seeked' event, unthrottled by the 10s progress-save
    // interval — specifically so it starts the moment the threshold is
    // crossed rather than waiting for persist()'s own throttled cadence to
    // catch up. That gap mattered: persist() only runs every 10 real
    // seconds (or at unmount), so a viewer who crosses 90% via a seek and
    // then immediately navigates away could hit unmount as the very FIRST
    // persist() call to observe completion, giving this async advance (a
    // check-then-maybe-write round trip, see below) a head start of exactly
    // zero — which is what made the "old episode flashes before flipping"
    // gap visible in the first place. Hooking every position update instead
    // means the advance has however long the user keeps watching/interacting
    // after crossing 90% as its head start, which in every realistic case is
    // far more than the round-trip needs; guarded by nextEpisodeAdvancedRef
    // so the (cheap) ratio check on every tick only ever does real async
    // work once.
    function maybeAdvanceFrontier() {
      if (!s || nextEpisodeAdvancedRef.current || !s.nextEpisode) return
      const { time, duration } = lastKnownRef.current
      if (duration <= 0 || time / duration < COMPLETED_THRESHOLD) return
      nextEpisodeAdvancedRef.current = true
      const next = s.nextEpisode
      // upsert_watch_progress overwrites position_seconds unconditionally on
      // every save, so this has to check for an existing row on the next
      // episode first — otherwise a viewer who'd already made real progress
      // there in an earlier session would get silently reset to 0.
      getEpisodeProgress(next.episodeUrl)
        .then((existing) => {
          const patched: Partial<ProgressEntry> = existing
            ? {
                episode_url: next.episodeUrl,
                season: next.season,
                episode_number: next.episodeNumber,
                episode_title: next.episodeTitle ?? '',
                position_seconds: existing.position_seconds,
                duration_seconds: existing.duration_seconds,
                completed: existing.completed,
                preview_url: existing.preview_url,
              }
            : {
                episode_url: next.episodeUrl,
                season: next.season,
                episode_number: next.episodeNumber,
                episode_title: next.episodeTitle ?? '',
                position_seconds: 0,
                duration_seconds: 0,
                completed: false,
                preview_url: undefined,
              }
          // Always writes — even when a row already exists — specifically to
          // force `started: true` on it. get_continue_watching's `started = 1`
          // filter (db.py) is otherwise the actual gate on becoming the
          // reported frontier, and the backend infers `started` purely from
          // `position_seconds > 30`: a *pre-existing* row for the next
          // episode (e.g. a stray few-second dip from earlier, or from this
          // exact advance flow running before this fix existed) can sit there
          // with position well under 30s and started=0 forever, silently
          // excluded from the frontier query no matter how "should be the
          // frontier now" it obviously is — leaving the OLD (real,
          // started=1) finished episode as the reported frontier
          // indefinitely, which is exactly the "shows the old episode, then
          // only later flips" symptom this whole mechanism exists to
          // prevent. The write itself is a no-op for position/duration/
          // completed when reusing `existing`'s own values (upsert_watch_
          // progress overwrites unconditionally, but with the same values
          // that's harmless) — only `started` actually changes.
          const write = saveProgress({
            episode_url: next.episodeUrl,
            series_title: s.seriesTitle,
            series_url: s.seriesUrl,
            season: next.season,
            episode_number: next.episodeNumber,
            episode_title: next.episodeTitle,
            position_seconds: existing?.position_seconds ?? 0,
            duration_seconds: existing?.duration_seconds ?? 0,
            completed: existing?.completed ?? false,
            started: true,
          })
          return write.then(() => {
            queryClient.setQueryData<ProgressEntry[]>(['progress', 'continue'], (old) =>
              old?.map((item) => (item.series_url === s.seriesUrl ? { ...item, ...patched } : item)),
            )
          })
        })
        .catch(() => {
          // The advance lookup/write itself failed — fall back to at least
          // showing the finished episode's real state instead of nothing,
          // and leave it to ContinueCell's own client-side fallback query
          // (findNextEpisodeAfter, gated on p.completed) to resolve the next
          // episode the slower way.
          queryClient.setQueryData<ProgressEntry[]>(['progress', 'continue'], (old) =>
            old?.map((item) =>
              item.episode_url === s.episodeUrl
                ? { ...item, position_seconds: lastKnownRef.current.time, duration_seconds: lastKnownRef.current.duration, completed: true }
                : item,
            ),
          )
        })
    }

    // Tracked on every tick — and on every seek, which updates currentTime
    // immediately but doesn't wait for the next timeupdate tick to reflect
    // it — and read from here, not from videoRef.current, when this effect's
    // own cleanup runs on unmount. HlsPlayer is a child component whose own
    // cleanup (hls.destroy()) runs before this parent effect's cleanup,
    // which can already reset/detach the <video> element's currentTime by
    // the time persist() would otherwise read it live — silently saving a
    // near-zero position and discarding whatever the user just watched.
    function trackTime() {
      const v = videoRef.current
      if (v) lastKnownRef.current = { time: v.currentTime, duration: v.duration || 0 }
      maybeAdvanceFrontier()
    }

    function onTimeUpdate() {
      trackTime()
      const now = Date.now()
      if (now - lastSaved >= PROGRESS_SAVE_INTERVAL_MS) {
        lastSaved = now
        persist()
      }
    }

    function onEnded() {
      persist(true)
    }

    video?.addEventListener('timeupdate', onTimeUpdate)
    video?.addEventListener('seeked', trackTime)
    video?.addEventListener('ended', onEnded)
    return () => {
      video?.removeEventListener('timeupdate', onTimeUpdate)
      video?.removeEventListener('seeked', trackTime)
      video?.removeEventListener('ended', onEnded)
      persist()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s, streamUrl])

  function goToNext() {
    if (!s?.nextEpisode) return
    // Guards against a repeat click on the "next episode" button/card, and
    // against a manual click racing the auto-advance countdown reaching
    // zero at the same moment — either way, only the first call proceeds.
    if (!claimNavigation()) return
    // Navigates immediately — language is already known synchronously
    // (carried over from the episode we're leaving), but *this* hop's own
    // next-episode-after-that isn't, and used to be awaited here before
    // navigating at all. Left for DownloadPlayPage to resolve after arrival
    // instead, same reasoning as HomePage's resumeContinueWatching: without
    // it, the episode we're jumping to would start with hasNext false,
    // silently disabling auto-advance for every episode after the first one
    // in a binge chain, *and* the click would sit unresponsive for a
    // network round-trip with nothing visibly happening in the meantime.
    const downloadState: DownloadPlayState = {
      episodeUrl: s.nextEpisode.episodeUrl,
      seriesTitle: s.seriesTitle,
      seriesUrl: s.seriesUrl,
      season: s.nextEpisode.season,
      episodeNumber: s.nextEpisode.episodeNumber,
      episodeTitle: s.nextEpisode.episodeTitle,
      absoluteEpisodeNumber: s.nextEpisode.absoluteEpisodeNumber,
      language: s.language,
      provider: s.provider,
      customPathId: s.customPathId,
    }
    navigate('/download-play', { replace: true, state: downloadState })
    releaseNavigation()
  }

  if (!s) {
    navigate('/', { replace: true })
    return null
  }

  return (
    <div className="player-page" ref={containerRef}>
      {/* Always mounted (even before streamUrl resolves) so the <video> DOM
          node — and therefore videoRef.current — exists from PlayerPage's
          first render. PlayerControls' listener-attaching effect runs once
          on mount with dependency [videoRef] (a stable ref object that never
          changes identity), so if HlsPlayer mounted conditionally later, that
          effect would already be done running with videoRef.current still
          null and would never re-attach listeners to the real element. */}
      <HlsPlayer src={streamUrl ?? ''} onLoadedMetadata={handleLoadedMetadata} ref={videoRef} />
      <div className="pl-grain" />
      <div className="pl-vignette" />
      <PlayerControls
        videoRef={videoRef}
        containerRef={containerRef}
        title={s.seriesTitle}
        subtitle={`S${String(s.season).padStart(2, '0')}E${String(s.episodeNumber).padStart(2, '0')}${
          s.absoluteEpisodeNumber != null ? ` · Episode ${s.absoluteEpisodeNumber} gesamt` : ''
        }${s.episodeTitle ? ` — ${s.episodeTitle}` : ''}`}
        onBack={() => navigate(-1)}
        skipTimes={skipTimes}
        thumbnails={thumbnails}
        hasNext={!!s.nextEpisode}
        onNext={goToNext}
      />
    </div>
  )
}
