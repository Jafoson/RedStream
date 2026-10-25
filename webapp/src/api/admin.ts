// Admin dashboard — src/aniworld/web/admin_api.py (+ the admin-access gate in
// webapp_auth.py). The admin token is separate from the normal bearer token:
// it is only issued after a second approval in the server terminal, only
// works for /api/admin/*, and stays valid for this browser until revoked.
import { ApiError, apiFetch } from './client'

const ADMIN_TOKEN_KEY = 'rstv_admin_token'
const ADMIN_DEVICE_KEY = 'rstv_admin_device_id'

export function getAdminToken(): string | null {
  return localStorage.getItem(ADMIN_TOKEN_KEY)
}

export function setAdminToken(token: string | null): void {
  if (token) localStorage.setItem(ADMIN_TOKEN_KEY, token)
  else localStorage.removeItem(ADMIN_TOKEN_KEY)
}

export function getAdminDeviceId(): string | null {
  return localStorage.getItem(ADMIN_DEVICE_KEY)
}

export function setAdminDeviceId(id: string | null): void {
  if (id) localStorage.setItem(ADMIN_DEVICE_KEY, id)
  else localStorage.removeItem(ADMIN_DEVICE_KEY)
}

export interface AdminAccessRequest {
  device_id: string
  status: 'pending'
  code: string
}

export interface AdminAccessPoll {
  status: 'pending' | 'approved' | 'denied' | 'revoked' | 'used'
  token?: string
}

export function requestAdminAccess(): Promise<AdminAccessRequest> {
  return apiFetch<AdminAccessRequest>('/api/webapp/admin-access', { method: 'POST', skipProfile: true })
}

export function pollAdminAccess(deviceId: string): Promise<AdminAccessPoll> {
  return apiFetch<AdminAccessPoll>(`/api/webapp/admin-access/${encodeURIComponent(deviceId)}`, {
    skipProfile: true,
  })
}

/** Like apiFetch, but with the admin token; a 401 drops the stored token. */
async function adminFetch<T>(
  path: string,
  options: {
    method?: 'GET' | 'POST' | 'DELETE'
    params?: Record<string, string | number | undefined>
    body?: unknown
  } = {},
): Promise<T> {
  try {
    return await apiFetch<T>(path, {
      ...options,
      skipProfile: true,
      headers: { 'X-Admin-Token': getAdminToken() ?? '' },
    })
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) setAdminToken(null)
    throw err
  }
}

export interface AdminSession {
  id: number
  approved_at: string | null
  ip_address: string | null
}

export type AccessKind = 'webapp' | 'admin'
export type AccessStatus = 'pending' | 'approved' | 'denied' | 'revoked'

export interface AccessRequestRow {
  id: number
  kind: AccessKind
  code: string | null
  status: AccessStatus
  ip_address: string | null
  user_agent: string | null
  requested_at: string
  decided_at: string | null
}

export interface AdminProfile {
  id: number
  name: string
  avatar_color: string
  entries: number
  completed: number
  last_watched: string | null
}

export interface HistoryEntry {
  id: number
  profile_id: number
  profile_name: string | null
  profile_color: string | null
  episode_url: string
  series_title: string | null
  series_url: string | null
  season: number
  episode_number: number
  episode_title: string | null
  position_seconds: number
  duration_seconds: number
  completed: number
  updated_at: string
}

export const getAdminSession = () => adminFetch<AdminSession>('/api/admin/session')

export const adminLogout = () => adminFetch<{ ok: true }>('/api/admin/logout', { method: 'POST' })

export const listAccessRequests = () =>
  adminFetch<{ requests: AccessRequestRow[]; current_session_id: number }>('/api/admin/access-requests')

export type AccessAction = 'approve' | 'deny' | 'revoke'

export const decideAccessRequest = (id: number, action: AccessAction) =>
  adminFetch<{ ok: true }>(`/api/admin/access-requests/${id}/${action}`, { method: 'POST' })

export interface BulkResult {
  done: number[]
  failed: { id: number; error: string }[]
}

export const bulkDecideAccessRequests = (ids: number[], action: AccessAction) =>
  adminFetch<BulkResult>('/api/admin/access-requests/bulk', { method: 'POST', body: { ids, action } })

export const listAdminProfiles = () => adminFetch<{ profiles: AdminProfile[] }>('/api/admin/profiles')

export type EpisodeSort = 'recent' | 'oldest' | 'episode' | 'episode_desc' | 'title'
export type SeriesSort = 'recent' | 'title' | 'latest_episode' | 'episodes'

export const getWatchHistory = (params: {
  profile_id?: number
  q?: string
  series_url?: string
  sort?: EpisodeSort
  limit: number
  offset: number
}) => adminFetch<{ entries: HistoryEntry[]; total: number }>('/api/admin/history', { params })

export interface HistorySeries {
  profile_id: number
  profile_name: string | null
  profile_color: string | null
  series_key: string
  series_url: string | null
  series_title: string | null
  episodes: number
  completed: number
  latest_season: number
  latest_episode: number
  last_season?: number
  last_episode?: number
  last_episode_title?: string | null
  last_completed?: number
  last_watched: string
}

export const getWatchHistorySeries = (params: {
  profile_id?: number
  q?: string
  sort?: SeriesSort
  limit: number
  offset: number
}) => adminFetch<{ series: HistorySeries[]; total: number }>('/api/admin/history/series', { params })

export const deleteHistoryEntry = (id: number) =>
  adminFetch<{ ok: true }>(`/api/admin/history/${id}`, { method: 'DELETE' })

export const deleteSeriesHistory = (profileId: number, seriesUrl: string) =>
  adminFetch<{ ok: true; deleted: number }>('/api/admin/history', {
    method: 'DELETE',
    params: { profile_id: profileId, series_url: seriesUrl },
  })
