// Bootstrap state machine mirroring app/lib/main.dart's _resolveInitScreen
// kIsWeb branch: on load, validate any stored token, then land on the
// web-access (device approval), profile-select, or ready state.
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import * as authApi from '../api/auth'
import { ApiError, getActiveProfileId, getToken, setActiveProfileId, setToken } from '../api/client'

export type AuthState = 'bootstrapping' | 'web-access' | 'needs-profile' | 'ready'

interface AuthContextValue {
  state: AuthState
  user: authApi.AuthUser | null
  /** Re-runs the bootstrap check — call after a device gets approved, or
   * after a profile is selected. */
  refresh: () => Promise<void>
  /** "Zugriff widerrufen" in Settings: clears the token and profile, sends
   * the user back to the web-access (device approval) screen. */
  logout: () => void
  selectProfile: (id: number) => void
  /** Sidebar's "Profil wechseln" — unlike logout(), keeps the device's auth
   * token intact and only clears the active profile, returning to the
   * profile-picker without re-triggering device approval. */
  switchProfile: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

function resolveState(hasToken: boolean, hasProfile: boolean): AuthState {
  if (!hasToken) return 'web-access'
  return hasProfile ? 'ready' : 'needs-profile'
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>('bootstrapping')
  const [user, setUser] = useState<authApi.AuthUser | null>(null)

  const refresh = useCallback(async () => {
    const token = getToken()
    if (!token) {
      setUser(null)
      setState('web-access')
      return
    }

    try {
      const me = await authApi.me()
      setUser(me)
      setState(resolveState(true, getActiveProfileId() !== null))
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setToken(null)
        setUser(null)
        setState('web-access')
      } else {
        // Transient network error validating a stored token — surface the
        // web-access screen rather than getting stuck bootstrapping forever;
        // the token stays intact so a retry can succeed once connectivity
        // returns (the user just re-lands here, not truly logged out).
        setState('web-access')
      }
    }
  }, [])

  useEffect(() => {
    refresh()
  }, [refresh])

  const logout = useCallback(() => {
    setToken(null)
    setActiveProfileId(null)
    setUser(null)
    setState('web-access')
  }, [])

  const selectProfile = useCallback((id: number) => {
    setActiveProfileId(id)
    setState('ready')
  }, [])

  const switchProfile = useCallback(() => {
    setActiveProfileId(null)
    setState('needs-profile')
  }, [])

  const value: AuthContextValue = { state, user, refresh, logout, selectProfile, switchProfile }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
