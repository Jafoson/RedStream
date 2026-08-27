import { apiFetch } from './client'

export interface AuthUser {
  id: number
  username: string
  role: 'admin' | 'user'
}

export function me(): Promise<AuthUser> {
  return apiFetch<AuthUser>('/api/auth/me', { skipProfile: true })
}
