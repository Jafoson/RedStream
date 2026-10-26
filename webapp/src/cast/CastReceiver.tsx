// Makes this browser a "Bildschirm" the Android app can stream to (backend:
// web/cast.py). Sends a heartbeat with what's playing every 1.5 s and runs
// the commands the app queued for it: play an episode (under the sender's
// profile), pause/resume/toggle, seek, stop. Renders nothing.
import { useEffect, useRef } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { apiFetch, getActiveProfileId } from '../api/client'
import { useAuth } from '../context/AuthContext'
import type { DownloadPlayState } from '../navigation/playerState'
import { getPlaybackState, getVideo } from './playback'
import { getScreenId, getScreenName, isScreenEnabled, setScreenId } from './screenSettings'

const HEARTBEAT_MS = 1500

interface CastCommand {
  id: string
  type: 'play' | 'pause' | 'resume' | 'toggle' | 'seek' | 'stop'
  profile_id?: number | null
  episode_url?: string
  series_title?: string
  series_url?: string
  season?: number
  episode_number?: number
  episode_title?: string
  absolute_episode_number?: number | null
  language?: string
  provider?: string
  position?: number
  delta?: number
}

export function CastReceiver() {
  const navigate = useNavigate()
  const location = useLocation()
  const queryClient = useQueryClient()
  const { selectProfile } = useAuth()
  // Latest values for the interval callback without restarting it.
  const ctx = useRef({ navigate, pathname: location.pathname, selectProfile })
  ctx.current = { navigate, pathname: location.pathname, selectProfile }

  useEffect(() => {
    let stopped = false
    let inFlight = false

    function run(cmd: CastCommand) {
      const video = getVideo()
      switch (cmd.type) {
        case 'play': {
          if (!cmd.episode_url || !cmd.series_url || cmd.season == null || cmd.episode_number == null) return
          if (cmd.profile_id != null && cmd.profile_id !== getActiveProfileId()) {
            // Play under the phone's profile, so progress lands where its
            // owner expects it.
            ctx.current.selectProfile(cmd.profile_id)
            queryClient.invalidateQueries()
          }
          const state: DownloadPlayState = {
            episodeUrl: cmd.episode_url,
            seriesTitle: cmd.series_title || '',
            seriesUrl: cmd.series_url,
            season: cmd.season,
            episodeNumber: cmd.episode_number,
            episodeTitle: cmd.episode_title,
            absoluteEpisodeNumber: cmd.absolute_episode_number ?? null,
            language: cmd.language || undefined,
            provider: cmd.provider || 'VOE',
          }
          const replace = ctx.current.pathname === '/watch' || ctx.current.pathname === '/download-play'
          ctx.current.navigate('/download-play', { replace, state })
          return
        }
        case 'pause':
          video?.pause()
          return
        case 'resume':
          video?.play().catch(() => {})
          return
        case 'toggle':
          if (video) {
            if (video.paused) video.play().catch(() => {})
            else video.pause()
          }
          return
        case 'seek':
          if (video && video.duration) {
            const target = cmd.position != null ? cmd.position : video.currentTime + (cmd.delta ?? 0)
            video.currentTime = Math.max(0, Math.min(video.duration - 1, target))
          }
          return
        case 'stop':
          if (ctx.current.pathname === '/watch' || ctx.current.pathname === '/download-play') {
            ctx.current.navigate('/', { replace: true })
          }
          return
      }
    }

    async function beat() {
      if (stopped || inFlight || !isScreenEnabled()) return
      inFlight = true
      try {
        const res = await apiFetch<{ screen_id: string; commands: CastCommand[] }>('/api/cast/heartbeat', {
          method: 'POST',
          body: { screen_id: getScreenId(), name: getScreenName(), state: getPlaybackState() },
        })
        if (res.screen_id !== getScreenId()) setScreenId(res.screen_id)
        for (const cmd of res.commands) run(cmd)
      } catch {
        // offline / server restarting — next beat retries
      } finally {
        inFlight = false
      }
    }

    function unregister() {
      const id = getScreenId()
      if (id) apiFetch(`/api/cast/screens/${encodeURIComponent(id)}`, { method: 'DELETE' }).catch(() => {})
    }

    function onSettings() {
      if (!isScreenEnabled()) unregister()
      else beat()
    }

    const timer = setInterval(beat, HEARTBEAT_MS)
    beat()
    window.addEventListener('rstv-screen-settings', onSettings)
    return () => {
      stopped = true
      clearInterval(timer)
      window.removeEventListener('rstv-screen-settings', onSettings)
    }
  }, [queryClient])

  return null
}
