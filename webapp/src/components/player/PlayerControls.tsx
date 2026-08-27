// Full "RedStream TV" player chrome (.pl-*) wired to real video/skip/next
// state — Player owns its own local focus model + keydown listener (matches
// the source design's app.jsx bailing out of the shared focus engine
// entirely while a player is open) rather than the {region,row,col} engine
// used by the rest of the app.
import { useCallback, useEffect, useRef, useState, type RefObject } from 'react'
import type { SkipTimes, ThumbnailMeta } from '../../api/stream'
import { thumbnailSpriteUrl } from '../../api/stream'
import { useSuspendFocusEngine } from '../../tv/FocusEngine'
import { Icon } from '../layout/icons'
import './PlayerControls.css'

const HIDE_MS = 4200
// Exported so PlayerPage.tsx's background segment-prefetch effect arms at
// exactly the same "last N seconds" point as this card, rather than
// duplicating the number and risking the two drifting apart.
export const AUTO_ADVANCE_THRESHOLD_S = 40
const AUTO_ADVANCE_COUNTDOWN_S = 10
const SEEK_COMMIT_DELAY_MS = 400

// Netflix-style hold-to-seek: repeated Left/Right presses in quick
// succession step further each time instead of a flat amount, so a held key
// (which fires key-repeat events) accelerates the longer it's held.
function seekStepFor(heldMs: number): number {
  if (heldMs < 800) return 10
  if (heldMs < 2000) return 20
  if (heldMs < 4000) return 35
  return 60
}

// Normalizes a keydown event down to the handful of key names this player
// cares about, checking e.code/e.keyCode as fallbacks alongside e.key — most
// notably, the numpad Enter key reports a distinct e.code ('NumpadEnter')
// while e.key is 'Enter' on both in every browser this was tested against,
// but this covers the numpad case explicitly too rather than assuming.
// Arrow keys additionally fall back to e.keyCode (37/38/39/40 — the classic
// VK_LEFT/UP/RIGHT/DOWN values, unchanged since Netscape 4 and still the
// most universally consistent of the three) and the older, pre-UI-Events-L3
// e.key names 'Up'/'Down'/'Left'/'Right' — e.g. Vewd/Opera TV Store's own
// developer docs recommend `event.key == 'Up'`, and a remote-synthesized
// KeyboardEvent (no real physical keyboard behind a TV remote's D-pad) may
// not populate e.code at all.
function normalizeKey(e: KeyboardEvent): string {
  if (e.key === 'Enter' || e.code === 'Enter' || e.code === 'NumpadEnter' || e.keyCode === 13) return 'Enter'
  if (e.key === ' ' || e.code === 'Space' || e.keyCode === 32) return ' '
  if (e.key === 'Escape' || e.code === 'Escape' || e.keyCode === 27) return 'Escape'
  if (e.key === 'Backspace' || e.code === 'Backspace' || e.keyCode === 8) return 'Backspace'
  if (e.key === 'ArrowUp' || e.key === 'Up' || e.code === 'ArrowUp' || e.keyCode === 38) return 'ArrowUp'
  if (e.key === 'ArrowDown' || e.key === 'Down' || e.code === 'ArrowDown' || e.keyCode === 40) return 'ArrowDown'
  if (e.key === 'ArrowLeft' || e.key === 'Left' || e.code === 'ArrowLeft' || e.keyCode === 37) return 'ArrowLeft'
  if (e.key === 'ArrowRight' || e.key === 'Right' || e.code === 'ArrowRight' || e.keyCode === 39) return 'ArrowRight'
  return e.key
}

function fmt(sec: number): string {
  sec = Math.max(0, Math.round(sec))
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = sec % 60
  const pad = (n: number) => String(n).padStart(2, '0')
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

type FocusId = 'back' | 'fullscreen' | 'scrub' | 'rew' | 'play' | 'fwd' | 'volume' | 'next' | 'skip' | 'nextcard'

const VOLUME_KEY = 'rstv_volume'
function loadStoredVolume(): number {
  try {
    const raw = localStorage.getItem(VOLUME_KEY)
    const v = raw !== null ? parseFloat(raw) : 1
    return Number.isFinite(v) ? Math.max(0, Math.min(1, v)) : 1
  } catch {
    return 1
  }
}

export interface PlayerControlsProps {
  videoRef: RefObject<HTMLVideoElement | null>
  containerRef: RefObject<HTMLDivElement | null>
  title: string
  subtitle?: string
  onBack: () => void
  skipTimes?: SkipTimes | null
  thumbnails?: ThumbnailMeta | null
  hasNext: boolean
  onNext: () => void
}

export function PlayerControls({
  videoRef,
  containerRef,
  title,
  subtitle,
  onBack,
  skipTimes,
  thumbnails,
  hasNext,
  onNext,
}: PlayerControlsProps) {
  useSuspendFocusEngine()

  const [playing, setPlaying] = useState(false)
  const [buffering, setBuffering] = useState(true)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [visible, setVisible] = useState(true)
  const [hoverRatio, setHoverRatio] = useState<number | null>(null)
  const [seeking, setSeeking] = useState(false)
  const [seekPreview, setSeekPreview] = useState<number | null>(null)
  // countdown: the ticking number driving the auto-jump-at-zero; null means
  // no auto-jump is pending. nextCardVisible: whether the "next episode"
  // card is shown at all — stays true once armed even after the countdown
  // is cancelled, so the card remains reachable/clickable via Enter without
  // the automatic timer still running.
  const [countdown, setCountdown] = useState<number | null>(null)
  const [countdownCancelled, setCountdownCancelled] = useState(false)
  const [nextCardVisible, setNextCardVisible] = useState(false)
  const [focus, setFocusState] = useState<FocusId>('scrub')
  // Volume level (0-1) persists across episodes/sessions like every real
  // player does; muted is tracked separately from volume (matches
  // video.muted's own semantics — muting doesn't zero out the remembered
  // level, it just silences playback on top of it).
  const [volume, setVolumeState] = useState(loadStoredVolume)
  const [muted, setMuted] = useState(false)
  const [volumeHover, setVolumeHover] = useState(false)

  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const seekingTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const seekBarRef = useRef<HTMLDivElement>(null)
  const volumeBarRef = useRef<HTMLDivElement>(null)
  const armedRef = useRef(false)
  // Hold-to-seek session: accumulates repeated same-direction Left/Right
  // presses into one pending target instead of seeking the real <video> on
  // every keystroke — HLS seeking triggers a real network fetch + buffer
  // flush per call, so hammering it with key-repeat events was the actual
  // cause of playback appearing to "jump back to zero"/stutter, not just a
  // UX nicety. The real seek only commits once presses stop for a moment.
  const seekHoldRef = useRef<{ direction: 1 | -1; baseTime: number; totalDelta: number; startedAt: number } | null>(
    null,
  )
  const seekCommitTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const inIntro = !!skipTimes?.op && currentTime >= skipTimes.op.start && currentTime < skipTimes.op.end
  const inOutro = !!skipTimes?.ed && currentTime >= skipTimes.ed.start && currentTime < skipTimes.ed.end
  const skipVisible = !buffering && (inIntro || inOutro)
  const nextVisible = !buffering && hasNext && nextCardVisible
  const countdownActive = countdown !== null

  const R = useRef({ focus, visible, skipVisible, nextVisible, hasNext, countdownActive })
  R.current = { focus, visible, skipVisible, nextVisible, hasNext, countdownActive }

  const controlOrder: FocusId[] = hasNext ? ['rew', 'play', 'fwd', 'volume', 'next'] : ['rew', 'play', 'fwd', 'volume']

  const scheduleHide = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current)
    hideTimer.current = setTimeout(() => {
      if (!videoRef.current?.paused) setVisible(false)
    }, HIDE_MS)
  }, [videoRef])

  const reveal = useCallback(() => {
    setVisible(true)
    scheduleHide()
  }, [scheduleHide])

  function togglePlay() {
    const video = videoRef.current
    if (!video) return
    if (video.paused) video.play()
    else video.pause()
  }

  // Setting a real volume level (drag/click/ArrowUp-Down) also unmutes —
  // matches every real player's convention that adjusting the level is an
  // explicit "I want sound" signal, not just a level change that stays
  // silenced. Persisted immediately so the next episode/session remembers it.
  function setVolume(v: number) {
    const video = videoRef.current
    const clamped = Math.max(0, Math.min(1, v))
    setVolumeState(clamped)
    setMuted(false)
    if (video) {
      video.volume = clamped
      video.muted = false
    }
    try {
      localStorage.setItem(VOLUME_KEY, String(clamped))
    } catch {
      // localStorage unavailable -- volume just won't persist across reloads
    }
  }

  // Reads the live <video> element rather than the closed-over volume/muted
  // state — this is called from the keydown handler below, whose listener is
  // registered by a low-dependency-array effect (same stale-closure hazard
  // documented for seekBy/doSkip's use of video.duration in this file).
  function adjustVolume(delta: number) {
    const video = videoRef.current
    const current = video ? (video.muted ? 0 : video.volume) : muted ? 0 : volume
    setVolume(current + delta)
  }

  function toggleMute() {
    const video = videoRef.current
    setMuted((m) => {
      const next = !m
      if (video) video.muted = next
      return next
    })
  }

  function volumeFromEvent(e: { clientX: number }): number {
    const bar = volumeBarRef.current
    if (!bar) return 0
    const rect = bar.getBoundingClientRect()
    return Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
  }

  // Shared by every seek entry point: shows the target immediately via
  // seekPreview (so the bar/time labels jump straight to the right place)
  // while the actual video.currentTime assignment is asynchronous — HLS
  // seeking needs to fetch/buffer before the position "really" lands. The
  // 'seeked' listener below clears seekPreview once it has, so the display
  // hands off from "pending target" to "real position" only once they
  // already agree — never dips back to the pre-seek position in between.
  function commitSeek(video: HTMLVideoElement, target: number) {
    setSeekPreview(target)
    video.currentTime = target
  }

  function seekBy(delta: number) {
    const video = videoRef.current
    if (!video) return
    setSeeking(true)
    if (seekingTimer.current) clearTimeout(seekingTimer.current)
    seekingTimer.current = setTimeout(() => setSeeking(false), 650)
    // video.duration (live DOM read), not the `duration` state var: this
    // function is invoked from the keydown handler below, whose closure is
    // captured once by a low-dependency effect and can otherwise go stale
    // long before the state variable updates, clamping every seek to 0.
    commitSeek(video, Math.max(0, Math.min(video.duration || 0, video.currentTime + delta)))
    reveal()
  }

  function seekToRatio(ratio: number) {
    const video = videoRef.current
    const dur = video?.duration || 0
    if (!video || dur <= 0) return
    seekHoldRef.current = null
    commitSeek(video, Math.max(0, Math.min(dur, ratio * dur)))
  }

  // Accumulates repeated same-direction presses into one pending target
  // (shown via seekPreview, not committed to the real <video> yet) — see
  // seekHoldRef's comment above for why the real seek is debounced.
  function seekHold(direction: 1 | -1) {
    const video = videoRef.current
    const dur = video?.duration || 0
    if (!video || dur <= 0) return
    const now = Date.now()
    let hold = seekHoldRef.current
    if (!hold || hold.direction !== direction) {
      hold = { direction, baseTime: seekPreview ?? video.currentTime, totalDelta: 0, startedAt: now }
      seekHoldRef.current = hold
    }
    hold.totalDelta += seekStepFor(now - hold.startedAt) * direction
    const target = Math.max(0, Math.min(dur, hold.baseTime + hold.totalDelta))
    setSeekPreview(target)
    setSeeking(true)
    reveal()

    if (seekCommitTimer.current) clearTimeout(seekCommitTimer.current)
    seekCommitTimer.current = setTimeout(() => {
      commitSeek(video, target)
      seekHoldRef.current = null
      setSeeking(false)
    }, SEEK_COMMIT_DELAY_MS)
  }

  function ratioFromEvent(e: { clientX: number }): number {
    const bar = seekBarRef.current
    if (!bar) return 0
    const rect = bar.getBoundingClientRect()
    return Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
  }

  function toggleFullscreen() {
    const el = containerRef.current
    if (!el) return
    if (document.fullscreenElement) document.exitFullscreen()
    else el.requestFullscreen?.()
  }

  function doSkip() {
    const video = videoRef.current
    const dur = video?.duration || 0
    const end = inIntro ? skipTimes!.op!.end : inOutro ? skipTimes!.ed!.end : null
    if (video && end !== null && dur > 0) {
      seekHoldRef.current = null
      commitSeek(video, Math.max(0, Math.min(dur, end)))
    }
    setFocusState('scrub')
    reveal()
  }

  // Applies the persisted volume once, on mount — the <video> element itself
  // (not its media source) is what carries .volume/.muted, and it stays
  // mounted across episode transitions within one viewing session (same
  // reasoning as HlsPlayer being "always mounted" — see PlayerPage.tsx), so
  // this only needs to run once, not per-episode.
  useEffect(() => {
    const video = videoRef.current
    if (!video) return
    video.volume = volume
    video.muted = muted
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // ---- real video element listeners ----
  useEffect(() => {
    const video = videoRef.current
    if (!video) return
    const onTimeUpdate = () => {
      setCurrentTime(video.currentTime)
      setPlaying(!video.paused)
      if (video.duration) setDuration(video.duration)
    }
    const onDurationChange = () => setDuration(video.duration || 0)
    const onPlay = () => {
      setPlaying(true)
      scheduleHide()
    }
    const onPause = () => {
      setPlaying(false)
      setVisible(true)
      if (hideTimer.current) clearTimeout(hideTimer.current)
    }
    const onWaiting = () => setBuffering(true)
    const onPlaying = () => setBuffering(false)
    const onCanPlay = () => setBuffering(false)
    // Fires once a seek actually lands — the one moment it's safe to stop
    // showing the pending target (seekPreview) and go back to displaying
    // the real, now-matching currentTime.
    const onSeeked = () => setSeekPreview(null)
    video.addEventListener('timeupdate', onTimeUpdate)
    video.addEventListener('durationchange', onDurationChange)
    video.addEventListener('play', onPlay)
    video.addEventListener('pause', onPause)
    video.addEventListener('waiting', onWaiting)
    video.addEventListener('playing', onPlaying)
    video.addEventListener('canplay', onCanPlay)
    video.addEventListener('seeked', onSeeked)
    return () => {
      video.removeEventListener('timeupdate', onTimeUpdate)
      video.removeEventListener('durationchange', onDurationChange)
      video.removeEventListener('play', onPlay)
      video.removeEventListener('pause', onPause)
      video.removeEventListener('waiting', onWaiting)
      video.removeEventListener('playing', onPlaying)
      video.removeEventListener('canplay', onCanPlay)
      video.removeEventListener('seeked', onSeeked)
    }
  }, [videoRef, scheduleHide])

  // ---- auto-advance: show the next-episode card once ≤40s remain, arm a
  // 10s countdown to auto-jump unless already cancelled this session ----
  useEffect(() => {
    if (!hasNext || duration <= 0) return
    const remaining = duration - currentTime
    if (remaining <= AUTO_ADVANCE_THRESHOLD_S && !armedRef.current) {
      armedRef.current = true
      setNextCardVisible(true)
      if (!countdownCancelled) setCountdown(AUTO_ADVANCE_COUNTDOWN_S)
    } else if (remaining > AUTO_ADVANCE_THRESHOLD_S && armedRef.current) {
      // Seeked back out of the window (e.g. rewound past it) — reset fully.
      armedRef.current = false
      setCountdownCancelled(false)
      setCountdown(null)
      setNextCardVisible(false)
    }
  }, [currentTime, duration, hasNext, countdownCancelled])

  useEffect(() => {
    if (countdown === null || countdown <= 0) {
      if (countdown === 0) onNext()
      return
    }
    const t = setTimeout(() => setCountdown((c) => (c !== null ? c - 1 : null)), 1000)
    return () => clearTimeout(t)
  }, [countdown, onNext])

  // ---- contextual auto-focus for floating prompts (matches player.jsx) ----
  useEffect(() => {
    if (skipVisible) setFocusState((f) => (f === 'scrub' || f === 'back' ? 'skip' : f))
    else setFocusState((f) => (f === 'skip' ? 'scrub' : f))
  }, [skipVisible])
  useEffect(() => {
    if (nextVisible) setFocusState('nextcard')
    else setFocusState((f) => (f === 'nextcard' ? 'scrub' : f))
  }, [nextVisible])

  // ---- key handling (own listener; FocusEngine is suspended) ----
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      // e.key alone reportedly misses real Enter presses for at least one
      // user (Space worked, Enter did nothing, everywhere in the player) —
      // not reproducible in this codebase's own Chromium-based testing, so
      // this reads e.code/e.keyCode as a fallback too (covers the numpad
      // Enter key's distinct `code`, and any browser/keyboard-layout
      // combination where `key` alone doesn't come through as plain
      // 'Enter'/' ').
      const k = normalizeKey(e)
      if (k === 'Escape' || k === 'Backspace') {
        e.preventDefault()
        if (R.current.countdownActive) {
          setCountdownCancelled(true)
          setCountdown(null)
        }
        onBack()
        return
      }
      if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter', ' '].includes(k)) return
      e.preventDefault()
      const s = R.current
      const isOk = k === 'Enter' || k === ' '
      // Any key except the activate/confirm one stops the ticking
      // auto-advance countdown — the card itself (nextCardVisible) stays up
      // so Enter can still jump to the next episode immediately later, it
      // just won't happen automatically anymore. Matches the user's own
      // input (seeking, navigating) as a clear "still watching this one"
      // signal.
      if (!isOk && s.countdownActive) {
        setCountdownCancelled(true)
        setCountdown(null)
      }
      if (!s.visible && !s.skipVisible && !s.nextVisible) {
        reveal()
        if (isOk) togglePlay()
        return
      }
      reveal()
      const f = s.focus

      if (f === 'skip') {
        if (isOk) doSkip()
        else if (k === 'ArrowDown' || k === 'ArrowLeft') setFocusState('scrub')
        return
      }
      if (f === 'nextcard') {
        if (isOk) onNext()
        // Otherwise: the cancel logic above already stopped the ticking
        // countdown — focus deliberately stays right here rather than
        // jumping to 'scrub' (the old behavior), since nothing else in this
        // focus model can navigate back to 'nextcard' via keyboard. Moving
        // away would strand the card unreachable except by mouse, breaking
        // "the popup stays and Enter still works" for D-pad/keyboard users.
        return
      }
      if (f === 'back') {
        if (isOk) onBack()
        else if (k === 'ArrowDown') setFocusState('scrub')
        else if (k === 'ArrowRight') setFocusState('fullscreen')
        return
      }
      if (f === 'fullscreen') {
        if (isOk) toggleFullscreen()
        else if (k === 'ArrowLeft') setFocusState('back')
        else if (k === 'ArrowDown') setFocusState(s.skipVisible ? 'skip' : 'scrub')
        return
      }
      if (f === 'volume') {
        const list = controlOrder
        const i = list.indexOf('volume')
        if (k === 'ArrowUp') adjustVolume(0.1)
        else if (k === 'ArrowDown') adjustVolume(-0.1)
        else if (k === 'ArrowLeft') setFocusState(i <= 0 ? 'scrub' : list[i - 1])
        else if (k === 'ArrowRight') setFocusState(list[Math.min(list.length - 1, i + 1)])
        else if (isOk) toggleMute()
        return
      }
      if (f === 'scrub') {
        if (k === 'ArrowLeft') seekHold(-1)
        else if (k === 'ArrowRight') seekHold(1)
        else if (k === 'ArrowUp') setFocusState(s.skipVisible ? 'skip' : 'back')
        else if (k === 'ArrowDown') setFocusState('play')
        else if (isOk) togglePlay()
        return
      }
      const list = controlOrder
      const i = list.indexOf(f)
      if (k === 'ArrowUp') setFocusState('scrub')
      else if (k === 'ArrowLeft') setFocusState(i <= 0 ? 'scrub' : list[i - 1])
      else if (k === 'ArrowRight') setFocusState(list[Math.min(list.length - 1, i + 1)])
      else if (isOk) {
        if (f === 'play') togglePlay()
        else if (f === 'rew') seekBy(-10)
        else if (f === 'fwd') seekBy(10)
        else if (f === 'next') onNext()
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onBack, onNext, reveal])

  // Cancel a pending hold-to-seek commit if the player closes mid-hold.
  useEffect(() => {
    return () => {
      if (seekCommitTimer.current) clearTimeout(seekCommitTimer.current)
    }
  }, [])

  // While a hold-to-seek is pending (seekPreview set, real seek not yet
  // committed), the bar/thumb/time labels track the pending target instead
  // of the still-actual playback position, matching the accumulate-then-jump
  // behavior in seekHold above.
  const displayTime = seekPreview ?? currentTime
  const progressRatio = duration > 0 ? displayTime / duration : 0
  const bufferedRatio = Math.min(1, progressRatio + 0.08)

  const hoverThumbStyle =
    hoverRatio !== null && thumbnails?.status === 'ready' && thumbnails.sprite_filepath
      ? (() => {
          const t = hoverRatio * duration
          const index = Math.min((thumbnails.total ?? 1) - 1, Math.max(0, Math.floor(t / (thumbnails.interval ?? 10))))
          const col = index % (thumbnails.cols ?? 1)
          const row = Math.floor(index / (thumbnails.cols ?? 1))
          return {
            // Quoted: downloaded-title folder names routinely contain literal
            // parentheses/brackets (e.g. "One Piece (1999-2026) [imdbid-…]"),
            // which are valid raw URL path characters but break an unquoted
            // CSS url() token — the browser then silently drops just this
            // declaration while keeping the rest of the inline style.
            backgroundImage: `url("${thumbnailSpriteUrl(thumbnails.sprite_filepath)}")`,
            backgroundPosition: `-${col * (thumbnails.thumb_w ?? 0)}px -${row * (thumbnails.thumb_h ?? 0)}px`,
            width: thumbnails.thumb_w,
            height: thumbnails.thumb_h,
            left: `${hoverRatio * 100}%`,
          }
        })()
      : null

  const onBtn = (id: FocusId) => ({
    onMouseEnter: () => {
      setFocusState(id)
      reveal()
    },
    onClick: () => {
      reveal()
      if (id === 'play') togglePlay()
      else if (id === 'rew') seekBy(-10)
      else if (id === 'fwd') seekBy(10)
      else if (id === 'next') onNext()
    },
  })

  return (
    <div className="player">
      {buffering && (
        <div className="pl-center">
          <div className="pl-spinner" />
        </div>
      )}

      <div className="pl-hit" onClick={() => { reveal(); togglePlay() }} />

      <div className={'pl-chrome' + (visible ? '' : ' hide')}>
        <div className="pl-scrim-top" />
        <div className="pl-scrim-bottom" />

        <div className="pl-top">
          <button
            type="button"
            className={'pl-back' + (focus === 'back' ? ' is-foc' : '')}
            onMouseEnter={() => {
              setFocusState('back')
              reveal()
            }}
            onClick={onBack}
          >
            <Icon name="back" w={20} />
            Zurück
          </button>
          <div className="pl-topright">
            <button
              type="button"
              className={'pl-back' + (focus === 'fullscreen' ? ' is-foc' : '')}
              onMouseEnter={() => {
                setFocusState('fullscreen')
                reveal()
              }}
              onClick={toggleFullscreen}
              style={{ padding: '0 16px' }}
            >
              ⛶
            </button>
            <div className="pl-wm">
              Red<b>Stream</b>
            </div>
          </div>
        </div>

        {!buffering && !playing && (
          <div className="pl-center">
            <div className="pl-bigplay">
              <Icon name="play" w={46} />
            </div>
          </div>
        )}

        <div className="pl-bottom">
          <div className="pl-titleblock">
            <h1 className="pl-title">{title}</h1>
            {subtitle && <div className="pl-eptitle">{subtitle}</div>}
          </div>

          <div className="pl-scrub">
            <span className="pl-time">{fmt(displayTime)}</span>
            <div
              className={'pl-track-wrap' + (focus === 'scrub' ? ' is-foc' : '')}
              ref={seekBarRef}
              onMouseMove={(e) => setHoverRatio(ratioFromEvent(e))}
              onMouseLeave={() => setHoverRatio(null)}
              onClick={(e) => {
                seekToRatio(ratioFromEvent(e))
                reveal()
                setFocusState('scrub')
              }}
            >
              {hoverThumbStyle && <div className="pl-nc-thumb pl-thumb-preview" style={hoverThumbStyle} />}
              <div className="pl-track">
                <div className="pl-buffered" style={{ width: `${bufferedRatio * 100}%` }} />
                <div className="pl-played" style={{ width: `${progressRatio * 100}%` }} />
                <div className="pl-thumb" style={{ left: `${progressRatio * 100}%` }}>
                  {(seeking || focus === 'scrub') && <div className="pl-bubble">{fmt(displayTime)}</div>}
                </div>
              </div>
            </div>
            <span className="pl-time rem">-{fmt(duration - displayTime)}</span>
          </div>

          <div className="pl-controls">
            <div className="pl-cmain">
              <button className={'pl-btn' + (focus === 'rew' ? ' is-foc' : '')} {...onBtn('rew')}>
                <span className="pl-blabel">10 Sek. zurück</span>-10
              </button>
              <button className={'pl-btn play' + (focus === 'play' ? ' is-foc' : '')} {...onBtn('play')}>
                <span className="pl-blabel">{playing ? 'Pause' : 'Abspielen'}</span>
                <Icon name={playing ? 'pause' : 'play'} w={30} />
              </button>
              <button className={'pl-btn' + (focus === 'fwd' ? ' is-foc' : '')} {...onBtn('fwd')}>
                <span className="pl-blabel">10 Sek. vor</span>+10
              </button>
            </div>
            <div
              className={'pl-cvolume' + (focus === 'volume' || volumeHover ? ' expanded' : '')}
              onMouseEnter={() => setVolumeHover(true)}
              onMouseLeave={() => setVolumeHover(false)}
            >
              <button
                className={'pl-btn pl-vol-btn' + (focus === 'volume' ? ' is-foc' : '')}
                onMouseEnter={() => {
                  setFocusState('volume')
                  reveal()
                }}
                onClick={() => {
                  reveal()
                  toggleMute()
                }}
              >
                <span className="pl-blabel">{muted || volume === 0 ? 'Stummschaltung aufheben' : 'Stumm'}</span>
                <Icon name={muted || volume === 0 ? 'volumeMute' : volume < 0.5 ? 'volumeLow' : 'volumeHigh'} w={22} />
              </button>
              <div
                className="pl-vol-track-wrap"
                ref={volumeBarRef}
                onClick={(e) => {
                  setVolume(volumeFromEvent(e))
                  reveal()
                  setFocusState('volume')
                }}
              >
                <div className="pl-vol-track">
                  <div className="pl-vol-fill" style={{ width: `${(muted ? 0 : volume) * 100}%` }} />
                  <div className="pl-vol-thumb" style={{ left: `${(muted ? 0 : volume) * 100}%` }} />
                </div>
              </div>
            </div>
            {hasNext && (
              <div className="pl-cside">
                <button className={'pl-btn' + (focus === 'next' ? ' is-foc' : '')} {...onBtn('next')}>
                  <span className="pl-blabel">Nächste Folge</span>
                  <Icon name="skipnext" w={26} />
                </button>
              </div>
            )}
          </div>

          <div className="pl-hint">
            <span>
              <kbd>←</kbd>
              <kbd>→</kbd> Spulen
            </span>
            <span className="sep" />
            <span>
              <kbd>Enter</kbd> Play / Pause
            </span>
            <span className="sep" />
            <span>
              <kbd>Esc</kbd> Zurück
            </span>
          </div>
        </div>
      </div>

      {skipVisible && (
        <button
          type="button"
          className={'pl-skip' + (focus === 'skip' ? ' is-foc' : '')}
          onMouseEnter={() => setFocusState('skip')}
          onClick={doSkip}
        >
          <Icon name="skipnext" w={22} />
          {inIntro ? 'Opening überspringen' : 'Abspann überspringen'}
        </button>
      )}

      {nextVisible && (
        <button
          type="button"
          className={'pl-nextcard' + (focus === 'nextcard' ? ' is-foc' : '')}
          onMouseEnter={() => setFocusState('nextcard')}
          onClick={onNext}
        >
          <div className="pl-nc-body">
            <div className="pl-nc-label">NÄCHSTE FOLGE</div>
            <div className="pl-nc-count">{countdown !== null ? `Spielt in ${countdown}s` : 'Weiter mit Enter'}</div>
          </div>
          <div className="pl-nc-play">
            <Icon name="play" w={20} />
          </div>
          {countdown !== null && (
            <>
              <div className="pl-nc-bar">
                <i style={{ width: `${((AUTO_ADVANCE_COUNTDOWN_S - countdown) / AUTO_ADVANCE_COUNTDOWN_S) * 100}%` }} />
              </div>
              <button
                type="button"
                className="filter"
                style={{ position: 'absolute', top: -44, right: 0 }}
                onClick={(e) => {
                  e.stopPropagation()
                  setCountdownCancelled(true)
                  setCountdown(null)
                }}
              >
                Abbrechen
              </button>
            </>
          )}
        </button>
      )}
    </div>
  )
}
