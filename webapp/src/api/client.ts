// Thin fetch wrapper shared by every module under src/api/. Adapted from
// react/src/api/client.ts, but TOKEN-ONLY: the device-approval flow this app
// uses never produces a session cookie, only a bearer token, so there is no
// `credentials: 'include'` here (unlike the /react dashboard, which supports
// both a cookie-based OIDC session and a bearer-token local login).

const TOKEN_KEY = 'rstv_token'
const PROFILE_KEY = 'rstv_profile_id'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null): void {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

export function getActiveProfileId(): number | null {
  const raw = localStorage.getItem(PROFILE_KEY)
  return raw ? Number(raw) : null
}

export function setActiveProfileId(id: number | null): void {
  if (id === null) localStorage.removeItem(PROFILE_KEY)
  else localStorage.setItem(PROFILE_KEY, String(id))
}

export class ApiError extends Error {
  status: number
  body: unknown
  constructor(message: string, status: number, body?: unknown) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.body = body
  }
}

export type QueryParams = Record<string, string | number | boolean | undefined | null>

function buildUrl(path: string, params?: QueryParams): string {
  const url = new URL(path, window.location.origin)
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined && value !== null && value !== '') {
        url.searchParams.set(key, String(value))
      }
    }
  }
  return url.pathname + url.search
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  body?: unknown
  params?: QueryParams
  signal?: AbortSignal
  /** Skip the X-Profile-ID header (auth/webapp-access endpoints don't need it). */
  skipProfile?: boolean
}

export function authHeaders(extra?: Record<string, string>): Record<string, string> {
  const headers: Record<string, string> = { ...extra }
  const token = getToken()
  if (token) headers['Authorization'] = `Bearer ${token}`
  return headers
}

export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, params, signal, skipProfile } = options

  const headers: Record<string, string> = {}
  if (!skipProfile) {
    const profileId = getActiveProfileId()
    if (profileId !== null) headers['X-Profile-ID'] = String(profileId)
  }
  const token = getToken()
  if (token) headers['Authorization'] = `Bearer ${token}`
  if (body !== undefined) headers['Content-Type'] = 'application/json'

  const res = await fetch(buildUrl(path, params), {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal,
  })

  if (res.status === 204) return undefined as T

  const contentType = res.headers.get('content-type') || ''
  const isJson = contentType.includes('application/json')
  const data = isJson ? await res.json().catch(() => null) : await res.text()

  if (!res.ok) {
    const message =
      isJson && data && typeof data === 'object' && 'error' in (data as Record<string, unknown>)
        ? String((data as Record<string, unknown>).error)
        : `Request failed (${res.status})`
    throw new ApiError(message, res.status, isJson ? data : undefined)
  }

  return data as T
}

/** URL for elements the browser loads directly (<img>, <video>, hls.js
 * manifest/segment requests) which can't attach fetch() headers themselves —
 * hls.js instead injects the Authorization header per-request via xhrSetup
 * (see components/player/HlsPlayer.tsx). */
export function apiUrl(path: string, params?: QueryParams): string {
  return buildUrl(path, params)
}
