// Google Cast (Chromecast, Android TV / Google TV) for the phone view, via
// Chrome's Cast sender SDK. The TV plays the stream itself with Google's
// Default Media Receiver, so the URL must work without login (relay or
// /api/share URL) and be reachable from the TV. Only Chrome (Android,
// desktop) offers this; elsewhere `available` stays false.
/* eslint-disable @typescript-eslint/no-explicit-any */

const SDK_URL = 'https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1'

export interface GCastStatus {
  /** SDK loaded and at least one Cast device on the network. */
  available: boolean
  /** Connected device name, or null. */
  device: string | null
  state: 'idle' | 'loading' | 'playing' | 'paused' | 'buffering'
  position: number
  duration: number
}

let status: GCastStatus = { available: false, device: null, state: 'idle', position: 0, duration: 0 }
let player: any = null
let controller: any = null
const listeners = new Set<(s: GCastStatus) => void>()

function emit(patch: Partial<GCastStatus>) {
  status = { ...status, ...patch }
  for (const l of listeners) l(status)
}

export function getGCastStatus(): GCastStatus {
  return status
}

export function subscribeGCast(l: (s: GCastStatus) => void): () => void {
  listeners.add(l)
  return () => listeners.delete(l)
}

function cf(): any {
  return (window as any).cast?.framework
}

function refreshFromPlayer() {
  if (!player) return
  const ps = player.playerState as string | null
  const state: GCastStatus['state'] =
    ps === 'PLAYING' ? 'playing' : ps === 'PAUSED' ? 'paused' : ps === 'BUFFERING' ? 'buffering' : player.isMediaLoaded ? 'loading' : 'idle'
  emit({ state, position: player.currentTime || 0, duration: player.duration || 0 })
}

let started = false

/** Loads the SDK once (Chrome only); safe to call repeatedly. */
export function initGoogleCast(): void {
  if (started) return
  started = true
  const w = window as any
  if (!w.chrome || /iPhone|iPad|iPod/.test(navigator.userAgent)) return
  w.__onGCastApiAvailable = (ok: boolean) => {
    if (!ok || !cf()) return
    const framework = cf()
    const ctx = framework.CastContext.getInstance()
    ctx.setOptions({
      receiverApplicationId: w.chrome.cast.media.DEFAULT_MEDIA_RECEIVER_APP_ID,
      autoJoinPolicy: w.chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED,
    })
    const castState = () => emit({ available: ctx.getCastState() !== framework.CastState.NO_DEVICES_AVAILABLE })
    ctx.addEventListener(framework.CastContextEventType.CAST_STATE_CHANGED, castState)
    ctx.addEventListener(framework.CastContextEventType.SESSION_STATE_CHANGED, () => {
      const session = ctx.getCurrentSession()
      emit({ device: session ? session.getCastDevice().friendlyName || 'Chromecast' : null })
      if (!session) emit({ state: 'idle', position: 0, duration: 0 })
    })
    player = new framework.RemotePlayer()
    controller = new framework.RemotePlayerController(player)
    controller.addEventListener(framework.RemotePlayerEventType.ANY_CHANGE, refreshFromPlayer)
    castState()
    const session = ctx.getCurrentSession()
    if (session) emit({ device: session.getCastDevice().friendlyName || 'Chromecast' })
  }
  const s = document.createElement('script')
  s.src = SDK_URL
  s.async = true
  document.head.appendChild(s)
}

/** Opens Chrome's device picker; resolves once connected (rejects if cancelled). */
export async function requestGCastSession(): Promise<void> {
  const framework = cf()
  if (!framework) throw new Error('Google Cast ist in diesem Browser nicht verfügbar')
  await framework.CastContext.getInstance().requestSession()
}

export function endGCastSession(): void {
  cf()?.CastContext.getInstance().endCurrentSession(true)
}

export interface GCastMedia {
  url: string
  title: string
  subtitle: string
  image?: string | null
  startTime: number
}

export async function loadGCastMedia(m: GCastMedia): Promise<void> {
  const w = window as any
  const session = cf()?.CastContext.getInstance().getCurrentSession()
  if (!session) throw new Error('Kein Chromecast verbunden')
  const media = new w.chrome.cast.media.MediaInfo(m.url, 'application/x-mpegurl')
  media.streamType = w.chrome.cast.media.StreamType.BUFFERED
  // Our HLS (downloads and most hosters) is MPEG-TS.
  media.hlsSegmentFormat = w.chrome.cast.media.HlsSegmentFormat?.TS
  media.hlsVideoSegmentFormat = w.chrome.cast.media.HlsVideoSegmentFormat?.MPEG2_TS
  const meta = new w.chrome.cast.media.TvShowMediaMetadata()
  meta.seriesTitle = m.title
  meta.title = m.subtitle
  if (m.image) meta.images = [new w.chrome.cast.Image(m.image)]
  media.metadata = meta
  const req = new w.chrome.cast.media.LoadRequest(media)
  req.currentTime = m.startTime
  req.autoplay = true
  const err = await session.loadMedia(req)
  if (err) throw new Error(String(err))
}

export function gcastToggle(): void {
  controller?.playOrPause()
}

export function gcastSeekBy(seconds: number): void {
  if (!player || !controller) return
  player.currentTime = Math.max(0, Math.min((player.duration || 0) - 1, (player.currentTime || 0) + seconds))
  controller.seek()
}

export function gcastStop(): void {
  controller?.stop()
}
