// Direct streaming — src/aniworld/web/live_stream.py. Plays an episode that
// isn't downloaded straight from the hoster, relayed through the backend
// (the hosters need Referer/Origin headers a browser can't send).
import { apiFetch } from './client'

export type LiveKind = 'hls' | 'file'

export interface LiveStream {
  url: string
  kind: LiveKind
  provider: string
}

export function resolveLiveStream(input: { episodeUrl: string; language?: string; provider?: string }): Promise<LiveStream> {
  return apiFetch<LiveStream>('/api/live/resolve', {
    method: 'POST',
    body: { episode_url: input.episodeUrl, language: input.language, provider: input.provider },
  })
}

// Per-browser preference (Settings → Wiedergabe); on unless switched off.
const DIRECT_STREAM_KEY = 'rstv_direct_stream'

export function isDirectStreamEnabled(): boolean {
  try {
    return localStorage.getItem(DIRECT_STREAM_KEY) !== '0'
  } catch {
    return true
  }
}

export function setDirectStreamEnabled(on: boolean): void {
  try {
    localStorage.setItem(DIRECT_STREAM_KEY, on ? '1' : '0')
  } catch {
    // private mode etc. — the default (on) applies
  }
}
