// Global (not per-component) guard against double-starting playback.
// Clicking Play, an episode row, a continue-watching card, or "next episode"
// all eventually call navigate('/download-play' | '/watch', ...) — but
// several of these handlers resolve the preferred language / next-episode
// reference asynchronously *before* navigating, and a second click landing
// in that window used to kick off a second, independent playback flow
// (visible as the video starting more than once). claimNavigation() returns
// true the first time and false for any call while a claim is still
// outstanding, so a handler can just bail out early on a repeat click.
// releaseNavigation() is called right after the real navigate() call, once
// the point being guarded against has passed — this is a short critical
// section around "click to navigate() actually firing", not a lock that
// spans the resulting page transition. The timeout is a safety net in case a
// caller bails out early (an error, a guard clause) without ever reaching
// navigate(), so a claim can never get stuck forever.
const CLAIM_TIMEOUT_MS = 8000

let claimed = false
let releaseTimer: ReturnType<typeof setTimeout> | null = null

export function claimNavigation(): boolean {
  if (claimed) return false
  claimed = true
  if (releaseTimer) clearTimeout(releaseTimer)
  releaseTimer = setTimeout(releaseNavigation, CLAIM_TIMEOUT_MS)
  return true
}

export function releaseNavigation(): void {
  claimed = false
  if (releaseTimer) {
    clearTimeout(releaseTimer)
    releaseTimer = null
  }
}
