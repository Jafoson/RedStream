// Admin dashboard (/verwaltung). Everything the terminal's --web-requests /
// --web-approve / --web-deny / --web-revoke can do for web app browsers, plus
// every profile's watch history (with the option to forget episodes again).
//
// Opening it needs a SECOND approval on top of the web app's own: this page
// asks for admin access, shows a code, and the server owner has to approve
// exactly that request in the terminal. Admin requests can never be approved
// from inside this dashboard — see admin_api.py's _decide().
import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  type AccessRequestRow,
  type HistoryEntry,
  adminLogout,
  decideAccessRequest,
  deleteHistoryEntry,
  deleteSeriesHistory,
  getAdminDeviceId,
  getAdminSession,
  getAdminToken,
  getWatchHistory,
  listAccessRequests,
  listAdminProfiles,
  pollAdminAccess,
  requestAdminAccess,
  setAdminDeviceId,
  setAdminToken,
} from '../api/admin'
import { ApiError } from '../api/client'
import { useBackHandler, useRegisterNav } from '../tv/FocusEngine'
import { Icon } from '../components/layout/icons'
import './AdminPage.css'

const POLL_INTERVAL_MS = 3000
const HISTORY_PAGE = 50

// SQLite's datetime('now') is UTC without a zone marker.
function parseUtc(value: string | null | undefined): Date | null {
  if (!value) return null
  const d = new Date(value.replace(' ', 'T') + 'Z')
  return Number.isNaN(d.getTime()) ? null : d
}

function formatTime(value: string | null | undefined): string {
  const d = parseUtc(value)
  return d
    ? d.toLocaleString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : '—'
}

function formatDuration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}` : `${m}:${String(sec).padStart(2, '0')}`
}

function errorText(err: unknown): string {
  return err instanceof Error ? err.message : 'Unbekannter Fehler'
}

// ── Gate ────────────────────────────────────────────────────────────────────

type GateState = 'checking' | 'idle' | 'requesting' | 'pending' | 'denied' | 'error' | 'ready'

function useAdminGate() {
  const [state, setState] = useState<GateState>(getAdminToken() ? 'checking' : 'idle')
  const [code, setCode] = useState<string | null>(null)
  const [requestId, setRequestId] = useState<string | null>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const stopPolling = useCallback(() => {
    if (pollRef.current !== null) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  const check = useCallback(async (deviceId: string) => {
    try {
      const result = await pollAdminAccess(deviceId)
      if (result.status === 'approved' && result.token) {
        stopPolling()
        setAdminDeviceId(null)
        setAdminToken(result.token)
        setState('ready')
      } else if (result.status !== 'pending') {
        // denied / revoked, or 'used' (the token went to another tab)
        stopPolling()
        setAdminDeviceId(null)
        setState('denied')
      }
    } catch {
      // keep polling through transient errors
    }
  }, [stopPolling])

  const startPolling = useCallback((deviceId: string) => {
    stopPolling()
    setRequestId(deviceId)
    setState('pending')
    pollRef.current = setInterval(() => check(deviceId), POLL_INTERVAL_MS)
    check(deviceId)
  }, [check, stopPolling])

  const request = useCallback(async () => {
    setState('requesting')
    try {
      const result = await requestAdminAccess()
      setAdminDeviceId(result.device_id)
      localStorage.setItem('rstv_admin_code', result.code)
      setCode(result.code)
      startPolling(result.device_id)
    } catch {
      setState('error')
    }
  }, [startPolling])

  useEffect(() => {
    if (getAdminToken()) {
      getAdminSession()
        .then(() => setState('ready'))
        .catch((err) => setState(err instanceof ApiError && err.status === 401 ? 'idle' : 'error'))
    } else {
      // Resume a request that was still pending when the page was left.
      const deviceId = getAdminDeviceId()
      if (deviceId) {
        setCode(localStorage.getItem('rstv_admin_code'))
        startPolling(deviceId)
      }
    }
    return stopPolling
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const lock = useCallback(() => {
    setAdminToken(null)
    setState('idle')
  }, [])

  return { state, code, requestId, request, lock }
}

function GateScreen({ state, code, onRequest }: { state: GateState; code: string | null; onRequest: () => void }) {
  return (
    <div className="admin-gate">
      <div className="admin-gate__card panel">
        <div className="admin-gate__icon">
          <Icon name="settings" w={26} />
        </div>
        <h1 className="text-title-lg">Admin-Bereich</h1>
        {(state === 'checking' || state === 'requesting') && <div className="spinner" />}
        {state === 'idle' && (
          <>
            <p className="text-body-lg admin-muted">
              Der Admin-Bereich braucht eine eigene Freigabe, die nur im Server-Terminal erteilt werden kann.
            </p>
            <button type="button" className="btn btn-primary" onClick={onRequest}>
              Admin-Zugriff anfragen
            </button>
          </>
        )}
        {state === 'pending' && (
          <>
            <div className="spinner" />
            <p className="text-body-lg admin-muted">Warte auf Freigabe im Terminal. Bestätigungscode:</p>
            <div className="admin-gate__code">{code ?? '······'}</div>
            <pre className="admin-gate__cmd">
              aniworld --web-requests{'\n'}aniworld --web-approve &lt;ID&gt;
            </pre>
            <p className="text-body-md admin-muted">
              Gib nur die Anfrage vom Typ <b>admin</b> mit genau diesem Code frei.
            </p>
          </>
        )}
        {state === 'denied' && (
          <>
            <p className="text-body-lg admin-error">Die Anfrage wurde abgelehnt oder ist nicht mehr gültig.</p>
            <button type="button" className="btn btn-primary" onClick={onRequest}>
              Erneut anfragen
            </button>
          </>
        )}
        {state === 'error' && (
          <>
            <p className="text-body-lg admin-error">Der Server konnte nicht erreicht werden.</p>
            <button type="button" className="btn btn-primary" onClick={onRequest}>
              Erneut versuchen
            </button>
          </>
        )}
      </div>
    </div>
  )
}

// ── Access requests tab ─────────────────────────────────────────────────────

const STATUS_LABEL: Record<string, string> = {
  pending: 'Wartet',
  approved: 'Freigegeben',
  denied: 'Abgelehnt',
  revoked: 'Widerrufen',
  expired: 'Abgelaufen',
}

function shortAgent(ua: string | null): string {
  if (!ua) return 'Unbekanntes Gerät'
  const browser = /Edg\//.test(ua) ? 'Edge' : /OPR\/|Opera/.test(ua) ? 'Opera' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : null
  const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Windows/.test(ua) ? 'Windows' : /Mac OS X/.test(ua) ? 'macOS' : /Tizen|Web0S|SMART-TV|SmartTV/i.test(ua) ? 'Smart-TV' : /Linux/.test(ua) ? 'Linux' : null
  return [browser, os].filter(Boolean).join(' · ') || ua.slice(0, 40)
}

function AccessTab({ onLocked }: { onLocked: () => void }) {
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState<number | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const { data, error } = useQuery({
    queryKey: ['admin', 'access-requests'],
    queryFn: listAccessRequests,
    refetchInterval: 5000,
  })

  useEffect(() => {
    if (error instanceof ApiError && error.status === 401) onLocked()
  }, [error, onLocked])

  const act = async (row: AccessRequestRow, action: 'approve' | 'deny' | 'revoke') => {
    if (action === 'revoke' && row.id === data?.current_session_id) {
      if (!window.confirm('Das ist deine aktuelle Admin-Sitzung. Wirklich widerrufen?')) return
    }
    setBusy(row.id)
    setMessage(null)
    try {
      await decideAccessRequest(row.id, action)
      if (action === 'revoke' && row.id === data?.current_session_id) {
        onLocked()
        return
      }
      await queryClient.invalidateQueries({ queryKey: ['admin', 'access-requests'] })
    } catch (err) {
      setMessage(errorText(err))
    } finally {
      setBusy(null)
    }
  }

  const rows = data?.requests ?? []
  const pending = rows.filter((r) => r.status === 'pending')
  const others = rows.filter((r) => r.status !== 'pending')

  const renderRow = (row: AccessRequestRow) => (
    <div key={row.id} className={'admin-row' + (row.status === 'pending' ? ' admin-row--pending' : '')}>
      <div className="admin-row__main">
        <div className="admin-row__title">
          <span className={'admin-badge admin-badge--' + row.kind}>{row.kind === 'admin' ? 'Admin' : 'Web-App'}</span>
          <span className="admin-row__id">#{row.id}</span>
          {row.code && <span className="admin-row__code">{row.code}</span>}
          <span className={'admin-status admin-status--' + row.status}>{STATUS_LABEL[row.status] ?? row.status}</span>
          {row.id === data?.current_session_id && <span className="admin-status admin-status--self">Diese Sitzung</span>}
        </div>
        <div className="admin-row__meta" title={row.user_agent ?? ''}>
          {shortAgent(row.user_agent)} · {row.ip_address || 'IP unbekannt'} · angefragt {formatTime(row.requested_at)}
          {row.kind === 'admin' && row.status === 'approved' && row.expires_at && <> · gültig bis {formatTime(row.expires_at)}</>}
        </div>
      </div>
      <div className="admin-row__actions">
        {row.status === 'pending' && row.kind === 'webapp' && (
          <button type="button" className="btn btn-primary btn-sm" disabled={busy === row.id} onClick={() => act(row, 'approve')}>
            Freigeben
          </button>
        )}
        {row.status === 'pending' && row.kind === 'admin' && (
          <span className="admin-hint">Freigabe nur im Terminal: <code>aniworld --web-approve {row.id}</code></span>
        )}
        {row.status === 'pending' && (
          <button type="button" className="filter btn-sm" disabled={busy === row.id} onClick={() => act(row, 'deny')}>
            Ablehnen
          </button>
        )}
        {row.status === 'approved' && (
          <button type="button" className="filter btn-sm admin-danger" disabled={busy === row.id} onClick={() => act(row, 'revoke')}>
            Widerrufen
          </button>
        )}
      </div>
    </div>
  )

  return (
    <>
      {message && <div className="admin-message">{message}</div>}
      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          Offene Anfragen ({pending.length})
        </div>
      </div>
      <div className="admin-list">
        {pending.length ? pending.map(renderRow) : <div className="admin-empty">Keine offenen Anfragen.</div>}
      </div>
      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          Alle Geräte
        </div>
      </div>
      <div className="admin-list">
        {others.length ? others.map(renderRow) : <div className="admin-empty">Noch keine Geräte.</div>}
      </div>
    </>
  )
}

// ── Watch history tab ───────────────────────────────────────────────────────

function HistoryTab({ onLocked }: { onLocked: () => void }) {
  const queryClient = useQueryClient()
  const [profileId, setProfileId] = useState<number | undefined>(undefined)
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [limit, setLimit] = useState(HISTORY_PAGE)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search.trim()), 300)
    return () => clearTimeout(t)
  }, [search])

  useEffect(() => setLimit(HISTORY_PAGE), [profileId, debounced])

  const profiles = useQuery({ queryKey: ['admin', 'profiles'], queryFn: listAdminProfiles })
  const history = useQuery({
    queryKey: ['admin', 'history', profileId, debounced, limit],
    queryFn: () => getWatchHistory({ profile_id: profileId, q: debounced || undefined, limit, offset: 0 }),
    placeholderData: keepPreviousData,
  })

  useEffect(() => {
    const err = history.error ?? profiles.error
    if (err instanceof ApiError && err.status === 401) onLocked()
  }, [history.error, profiles.error, onLocked])

  const refresh = () => queryClient.invalidateQueries({ queryKey: ['admin'] })

  const removeEntry = async (entry: HistoryEntry) => {
    const label = `${entry.series_title ?? 'Episode'} S${String(entry.season).padStart(2, '0')}E${String(entry.episode_number).padStart(2, '0')}`
    if (!window.confirm(`„${label}“ für ${entry.profile_name ?? 'dieses Profil'} als nicht gesehen markieren?`)) return
    setMessage(null)
    try {
      await deleteHistoryEntry(entry.id)
      await refresh()
    } catch (err) {
      setMessage(errorText(err))
    }
  }

  const removeSeries = async (entry: HistoryEntry) => {
    if (!entry.series_url) return
    if (!window.confirm(`Den kompletten Verlauf von „${entry.series_title ?? 'dieser Serie'}“ für ${entry.profile_name ?? 'dieses Profil'} löschen?`)) return
    setMessage(null)
    try {
      await deleteSeriesHistory(entry.profile_id, entry.series_url)
      await refresh()
    } catch (err) {
      setMessage(errorText(err))
    }
  }

  const entries = history.data?.entries ?? []
  const total = history.data?.total ?? 0

  return (
    <>
      {message && <div className="admin-message">{message}</div>}
      <div className="admin-profiles">
        <button type="button" className={'admin-profile' + (profileId === undefined ? ' on' : '')} onClick={() => setProfileId(undefined)}>
          <span className="admin-profile__name">Alle Profile</span>
        </button>
        {profiles.data?.profiles.map((p) => (
          <button key={p.id} type="button" className={'admin-profile' + (profileId === p.id ? ' on' : '')} onClick={() => setProfileId(p.id)}>
            <span className="admin-profile__avatar" style={{ background: p.avatar_color }}>
              {p.name.slice(0, 1).toUpperCase()}
            </span>
            <span>
              <span className="admin-profile__name">{p.name}</span>
              <span className="admin-profile__stats">
                {p.completed} gesehen · {p.entries} Einträge
                {p.last_watched && <> · zuletzt {formatTime(p.last_watched)}</>}
              </span>
            </span>
          </button>
        ))}
      </div>

      <input
        className="text-input admin-search"
        type="search"
        placeholder="Serie oder Episode suchen…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      <div className="admin-list">
        {entries.map((e) => {
          const pct = e.duration_seconds > 0 ? Math.min(100, (e.position_seconds / e.duration_seconds) * 100) : 0
          return (
            <div key={e.id} className="admin-row">
              <div className="admin-row__main">
                <div className="admin-row__title">
                  <span className="admin-profile__dot" style={{ background: e.profile_color ?? 'var(--muted-2)' }} />
                  <span className="admin-row__profile">{e.profile_name ?? `Profil ${e.profile_id}`}</span>
                  <span className="admin-row__series">{e.series_title || e.episode_url}</span>
                  <span className="admin-row__ep">
                    S{String(e.season).padStart(2, '0')}E{String(e.episode_number).padStart(2, '0')}
                  </span>
                  {e.completed ? (
                    <span className="admin-status admin-status--approved">Gesehen</span>
                  ) : (
                    <span className="admin-status admin-status--pending">{Math.round(pct)} %</span>
                  )}
                </div>
                {e.episode_title && <div className="admin-row__meta">{e.episode_title}</div>}
                <div className="admin-progress">
                  <div className="admin-progress__bar" style={{ width: `${e.completed ? 100 : pct}%` }} />
                </div>
                <div className="admin-row__meta">
                  {formatDuration(e.position_seconds)} / {formatDuration(e.duration_seconds)} · {formatTime(e.updated_at)}
                </div>
              </div>
              <div className="admin-row__actions">
                <button type="button" className="filter btn-sm admin-danger" onClick={() => removeEntry(e)}>
                  Als ungesehen markieren
                </button>
                {e.series_url && (
                  <button type="button" className="filter btn-sm" onClick={() => removeSeries(e)}>
                    Ganze Serie zurücksetzen
                  </button>
                )}
              </div>
            </div>
          )
        })}
        {!history.isLoading && entries.length === 0 && <div className="admin-empty">Kein Verlauf gefunden.</div>}
      </div>
      {entries.length < total && (
        <button type="button" className="btn btn-ghost admin-more" onClick={() => setLimit((l) => l + HISTORY_PAGE)}>
          Mehr laden ({entries.length} von {total})
        </button>
      )}
    </>
  )
}

// ── Page ────────────────────────────────────────────────────────────────────

type Tab = 'access' | 'history'

export function AdminPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const gate = useAdminGate()
  const [tab, setTab] = useState<Tab>('access')
  const session = useQuery({
    queryKey: ['admin', 'session'],
    queryFn: getAdminSession,
    enabled: gate.state === 'ready',
  })

  // Mouse/touch page: keep the TV focus engine from replaying the previous
  // screen's Enter action, and let Escape/Backspace go back to the app.
  useRegisterNav([], () => {}, [])
  useBackHandler(() => navigate('/'))

  const lock = gate.lock
  const onLocked = useCallback(() => {
    queryClient.removeQueries({ queryKey: ['admin'] })
    lock()
  }, [lock, queryClient])

  const logout = async () => {
    try {
      await adminLogout()
    } catch {
      // the token is dropped locally either way
    }
    onLocked()
  }

  return (
    <div className="admin-page">
      <header className="admin-header">
        <button type="button" className="back-btn" onClick={() => navigate('/')} aria-label="Zurück zur App">
          <Icon name="back" w={20} />
        </button>
        <div>
          <div className="grid-eyebrow">REDSTREAM</div>
          <h1 className="grid-h1">Admin-Bereich</h1>
        </div>
        {gate.state === 'ready' && (
          <div className="admin-header__session">
            {session.data && <span className="admin-muted text-body-md">Sitzung gültig bis {formatTime(session.data.expires_at)}</span>}
            <button type="button" className="filter" onClick={logout}>
              Admin abmelden
            </button>
          </div>
        )}
      </header>

      {gate.state !== 'ready' ? (
        <GateScreen state={gate.state} code={gate.code} onRequest={gate.request} />
      ) : (
        <>
          <div className="filters admin-tabs">
            <button type="button" className={'filter' + (tab === 'access' ? ' on' : '')} onClick={() => setTab('access')}>
              Zugriffe
            </button>
            <button type="button" className={'filter' + (tab === 'history' ? ' on' : '')} onClick={() => setTab('history')}>
              Verlauf
            </button>
          </div>
          <div className="admin-content">
            {tab === 'access' ? <AccessTab onLocked={onLocked} /> : <HistoryTab onLocked={onLocked} />}
          </div>
        </>
      )}
    </div>
  )
}
