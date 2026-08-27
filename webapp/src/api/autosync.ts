import { ApiError, apiFetch } from './client'

export interface AutosyncJob {
  id: number
  title: string
  series_url: string
  language: string
  provider: string
  enabled: boolean
  added_by: string | null
  custom_path_id?: number | null
}

export function getAutosyncJobs(): Promise<AutosyncJob[]> {
  return apiFetch<{ jobs: AutosyncJob[] }>('/api/autosync').then((r) => r.jobs)
}

export function checkAutosync(seriesUrl: string): Promise<AutosyncJob | null> {
  return apiFetch<{ exists: boolean; job: AutosyncJob | null }>('/api/autosync/check', {
    params: { url: seriesUrl },
  }).then((r) => (r.exists ? r.job : null))
}

export interface CreateAutosyncInput {
  title: string
  series_url: string
  language: string
  provider: string
  custom_path_id?: number | null
}

/** Creating a job the current profile already owns 409s — this reactivates
 * the existing job instead, mirroring the /react dashboard's SeriesModal fix
 * for the same conflict. */
export async function addAutosync(input: CreateAutosyncInput): Promise<void> {
  try {
    await apiFetch<void>('/api/autosync', { method: 'POST', body: input })
  } catch (err) {
    if (err instanceof ApiError && err.status === 409) {
      const existing = await checkAutosync(input.series_url)
      if (existing) {
        await apiFetch<void>(`/api/autosync/${existing.id}`, { method: 'PUT', body: { enabled: true } })
        return
      }
    }
    throw err
  }
}

export function removeAutosync(id: number): Promise<void> {
  return apiFetch<void>(`/api/autosync/${id}`, { method: 'DELETE' })
}
