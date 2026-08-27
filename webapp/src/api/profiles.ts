import { apiFetch } from './client'

export interface Profile {
  id: number
  name: string
  avatar_color: string
  default_language?: string | null
}

export function getProfiles(): Promise<Profile[]> {
  return apiFetch<{ profiles: Profile[] }>('/api/profiles', { skipProfile: true }).then((r) => r.profiles)
}

export interface CreateProfileInput {
  name: string
  avatar_color: string
  default_language?: string | null
}

export function createProfile(input: CreateProfileInput): Promise<number> {
  return apiFetch<{ id: number }>('/api/profiles', { method: 'POST', body: input, skipProfile: true }).then(
    (r) => r.id,
  )
}

export function updateProfile(id: number, input: Partial<CreateProfileInput>): Promise<void> {
  return apiFetch<void>(`/api/profiles/${id}`, { method: 'PUT', body: input, skipProfile: true })
}

export function deleteProfile(id: number): Promise<void> {
  return apiFetch<void>(`/api/profiles/${id}`, { method: 'DELETE', skipProfile: true })
}
