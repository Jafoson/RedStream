// Adapted from react/src/components/player/HlsPlayer.tsx's xhrSetup pattern,
// but exposes the raw <video> element via ref instead of owning its own UI —
// this app's PlayerControls builds a fully custom overlay (controls={false}).
import { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import { authHeaders } from '../../api/client'

export interface HlsPlayerProps {
  src: string
  /** 'file' = a plain video file (direct-stream MP4), played without hls.js. */
  kind?: 'hls' | 'file'
  /** Let the browser play HLS itself when it can (Safari) — needed for
   * AirPlay; `src` must then work without an auth header (relay or share URL). */
  native?: boolean
  onLoadedMetadata?: () => void
  /** Playback can't continue (hls.js fatal error / media error). */
  onFatalError?: (reason: string) => void
}

export const HlsPlayer = forwardRef<HTMLVideoElement, HlsPlayerProps>(function HlsPlayer(
  { src, kind = 'hls', native = false, onLoadedMetadata, onFatalError },
  ref,
) {
  const videoRef = useRef<HTMLVideoElement>(null)
  useImperativeHandle(ref, () => videoRef.current as HTMLVideoElement)
  const onFatalErrorRef = useRef(onFatalError)
  onFatalErrorRef.current = onFatalError

  useEffect(() => {
    const video = videoRef.current
    if (!video || !src) return
    let cancelled = false
    let hlsInstance: import('hls.js').default | null = null

    const onMediaError = () => onFatalErrorRef.current?.(video.error?.message || 'media error')
    video.addEventListener('error', onMediaError)

    // Direct-stream MP4: the relay URL carries its own capability token, so
    // the browser can load it natively (with Range requests for seeking).
    // Same for HLS with `native` in Safari (AirPlay only works that way).
    if (kind === 'file' || (native && video.canPlayType('application/vnd.apple.mpegurl'))) {
      video.src = src
      return () => {
        video.removeEventListener('error', onMediaError)
        video.removeAttribute('src')
        video.load()
      }
    }

    // Dynamically imported (a plain JS import(), not React.lazy) so hls.js's
    // ~700kB isn't downloaded until a stream URL is actually known — this
    // used to be achieved by wrapping the whole PlayerPage route in
    // React.lazy()+Suspense instead, which turned out to have a real,
    // measured cost: React schedules a lazy component's commit (and every
    // subsequent re-render while any Suspense boundary above it exists)
    // through a lower-priority "retry" lane rather than the normal
    // synchronous path, adding a reproducible ~300ms delay before the
    // player's own mount effects could even start running — confirmed by
    // removing React.lazy/Suspense from the route entirely and watching the
    // delay disappear (click-to-playable dropped from ~730ms to ~570ms in a
    // real measured test). A plain import() has no such effect on the
    // surrounding component tree's scheduling; only the concrete promise
    // callback below is deferred, not React's own commit priority for the
    // page it lives in.
    import('hls.js').then(({ default: Hls }) => {
      if (cancelled) return
      // The stream endpoint is auth-gated like the rest of /api/*, but a
      // plain <video src> load can't carry an Authorization header — hls.js's
      // xhrSetup lets us attach it to every manifest/segment request, which
      // native HLS playback can't do. So hls.js is used unconditionally here,
      // never only as a non-Safari fallback (same reasoning as react/'s
      // player).
      if (Hls.isSupported()) {
        // hls.js retries a failing fragment up to 6 times with growing
        // delays by default — for a direct stream whose hoster went away
        // that's half a minute of black screen before PlayerPage can fall
        // back to downloading. A short, bounded retry is plenty for both
        // that and local files.
        const retry = {
          maxTimeToFirstByteMs: 10000,
          maxLoadTimeMs: 60000,
          timeoutRetry: { maxNumRetry: 2, retryDelayMs: 0, maxRetryDelayMs: 0 },
          errorRetry: { maxNumRetry: 2, retryDelayMs: 1000, maxRetryDelayMs: 4000 },
        }
        const hls = new Hls({
          fragLoadPolicy: { default: retry },
          xhrSetup: (xhr) => {
            for (const [key, value] of Object.entries(authHeaders())) {
              xhr.setRequestHeader(key, value)
            }
          },
        })
        hlsInstance = hls
        let networkRetries = 0
        hls.on(Hls.Events.ERROR, (_event, data) => {
          if (!data.fatal) return
          if (data.type === Hls.ErrorTypes.NETWORK_ERROR && networkRetries < 1) {
            networkRetries += 1
            hls.startLoad()
            return
          }
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR && networkRetries < 1) {
            networkRetries += 1
            hls.recoverMediaError()
            return
          }
          onFatalErrorRef.current?.(data.details || 'hls error')
        })
        hls.loadSource(src)
        hls.attachMedia(video)
      } else {
        // Very old browsers with neither hls.js (MSE) nor auth-header
        // support — only works when the stream endpoint happens to be
        // reachable without one.
        video.src = src
      }
    })

    return () => {
      cancelled = true
      video.removeEventListener('error', onMediaError)
      hlsInstance?.destroy()
    }
  }, [src, kind, native])

  return (
    <video
      ref={videoRef}
      className="player-video"
      playsInline
      autoPlay
      x-webkit-airplay="allow"
      // Not a tab stop — this app has its own keyboard-driven focus model
      // (PlayerControls' onKey), and a <video> with real DOM focus responds
      // to some keys (notably Space) via the browser's own built-in
      // media-element shortcuts, independent of and possibly ahead of this
      // app's own handling.
      tabIndex={-1}
      onLoadedMetadata={onLoadedMetadata}
    />
  )
})
