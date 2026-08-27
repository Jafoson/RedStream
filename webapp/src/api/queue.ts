import { apiFetch } from './client'

export interface QueueItem {
  id: number
  title: string
  series_url: string
  episodes: string // JSON-encoded array of episode URLs
  total_episodes: number
  language: string
  provider: string
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'
  current_episode: number
  current_url: string | null
  errors: string // JSON-encoded array
  created_at: string
  completed_at: string | null
  priority: number
  progress?: number
}

export interface FfmpegProgress {
  percent: number
  time: string
  speed: string
  bandwidth: string
  active: boolean
}

export interface QueueState {
  items: QueueItem[]
  ffmpeg_progress: FfmpegProgress | Record<number, FfmpegProgress>
}

export function getQueue(): Promise<QueueState> {
  return apiFetch<QueueState>('/api/queue')
}

export interface EnqueueDownloadInput {
  title: string
  series_url: string
  episodes: string[]
  language: string
  provider: string
  custom_path_id?: number | null
  /** 0=watch-intent, 1=prefetch, 2=manual (default), 3=autosync */
  priority?: number
}

export function enqueueDownload(input: EnqueueDownloadInput): Promise<{ queue_id: number }> {
  return apiFetch<{ queue_id: number }>('/api/download', { method: 'POST', body: input })
}

export function findQueueItemByEpisode(episodeUrl: string): Promise<number | null> {
  return apiFetch<{ queue_id: number | null }>('/api/queue/find-by-episode', {
    params: { url: episodeUrl },
  }).then((r) => r.queue_id)
}

export function cancelQueueItem(id: number, force = false): Promise<void> {
  return apiFetch<void>(`/api/queue/${id}/cancel`, { method: 'POST', body: { force } })
}

export function removeQueueItem(id: number): Promise<void> {
  return apiFetch<void>(`/api/queue/${id}`, { method: 'DELETE' })
}

export function moveQueueItem(id: number, direction: 'up' | 'down'): Promise<void> {
  return apiFetch<void>(`/api/queue/${id}/move`, { method: 'POST', body: { direction } })
}

export function clearCompleted(): Promise<void> {
  return apiFetch<void>('/api/queue/completed', { method: 'DELETE' })
}
