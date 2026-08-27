// Adapted from react/src/components/player/HlsPlayer.tsx's xhrSetup pattern,
// but exposes the raw <video> element via ref instead of owning its own UI —
// this app's PlayerControls builds a fully custom overlay (controls={false}).
import { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import { authHeaders } from '../../api/client'

export interface HlsPlayerProps {
  src: string
  onLoadedMetadata?: () => void
}

export const HlsPlayer = forwardRef<HTMLVideoElement, HlsPlayerProps>(function HlsPlayer(
  { src, onLoadedMetadata },
  ref,
) {
  const videoRef = useRef<HTMLVideoElement>(null)
  useImperativeHandle(ref, () => videoRef.current as HTMLVideoElement)

  useEffect(() => {
    const video = videoRef.current
    if (!video || !src) return
    let cancelled = false
    let hlsInstance: import('hls.js').default | null = null

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
        const hls = new Hls({
          xhrSetup: (xhr) => {
            for (const [key, value] of Object.entries(authHeaders())) {
              xhr.setRequestHeader(key, value)
            }
          },
        })
        hlsInstance = hls
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
      hlsInstance?.destroy()
    }
  }, [src])

  return (
    <video
      ref={videoRef}
      className="player-video"
      playsInline
      autoPlay
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
