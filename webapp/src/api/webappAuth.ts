// Device-approval flow — src/aniworld/web/webapp_auth.py. Both endpoints are
// public/CSRF-exempt by design: a fresh browser has no token yet.
import { apiFetch } from './client'

export interface RequestAccessResult {
  device_id: string
  status: 'pending'
}

export interface PollAccessResult {
  status: 'pending' | 'approved' | 'denied' | 'revoked'
  token?: string
}

// Module-level (not component-instance) in-flight coalescing: two overlapping
// callers — e.g. React StrictMode's dev-only double-invoke of WebAccessPage's
// mount effect, which a component-scoped ref guard doesn't reliably survive
// under Vite's dev server — get the same in-flight promise instead of each
// POSTing their own request-access call. Without this, the second call wins
// the write to localStorage's device_id while the first's request is left
// forever orphaned server-side, silently pending and never polled again.
let inFlight: Promise<RequestAccessResult> | null = null

export function requestAccess(): Promise<RequestAccessResult> {
  if (inFlight) return inFlight
  inFlight = apiFetch<RequestAccessResult>('/api/webapp/request-access', {
    method: 'POST',
    skipProfile: true,
  }).finally(() => {
    inFlight = null
  })
  return inFlight
}

export function pollAccess(deviceId: string): Promise<PollAccessResult> {
  return apiFetch<PollAccessResult>(`/api/webapp/request-access/${encodeURIComponent(deviceId)}`, {
    skipProfile: true,
  })
}
