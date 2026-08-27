// Adapted from react/src/components/player/HlsPlayer.tsx's xhrSetup pattern,
// but exposes the raw <video> element via ref instead of owning its own UI —
// this app's PlayerControls builds a fully custom overlay (controls={false}).
import { forwardRef, useEffect, useImperativeHandle, useRef } from 'react'
import Hls from 'hls.js'
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

    // The stream endpoint is auth-gated like the rest of /api/*, but a plain
    // <video src> load can't carry an Authorization header — hls.js's
    // xhrSetup lets us attach it to every manifest/segment request, which
    // native HLS playback can't do. So hls.js is used unconditionally here,
    // never only as a non-Safari fallback (same reasoning as react/'s player).
    if (Hls.isSupported()) {
      const hls = new Hls({
        xhrSetup: (xhr) => {
          for (const [key, value] of Object.entries(authHeaders())) {
            xhr.setRequestHeader(key, value)
          }
        },
      })
      hls.loadSource(src)
      hls.attachMedia(video)
      return () => hls.destroy()
    }

    // Very old browsers with neither hls.js (MSE) nor auth-header support —
    // only works when the stream endpoint happens to be reachable without one.
    video.src = src
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
