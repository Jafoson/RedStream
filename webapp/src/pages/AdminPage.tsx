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
  type AccessAction,
  type AccessRequestRow,
  type EpisodeSort,
  type HistoryEntry,
  type HistorySeries,
  type SeriesSort,
  adminLogout,
  bulkDecideAccessRequests,
  deleteHistoryEntry,
  deleteSeriesHistory,
  getAdminDeviceId,
  getAdminSession,
  getAdminToken,
  getWatchHistory,
  getWatchHistorySeries,
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
}

const ACTION_DONE: Record<AccessAction, string> = {
  approve: 'freigegeben',
  deny: 'abgelehnt',
  revoke: 'widerrufen',
}

function shortAgent(ua: string | null): string {
  if (!ua) return 'Unbekanntes Gerät'
  const browser = /Edg\//.test(ua) ? 'Edge' : /OPR\/|Opera/.test(ua) ? 'Opera' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : null
  const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Windows/.test(ua) ? 'Windows' : /Mac OS X/.test(ua) ? 'macOS' : /Tizen|Web0S|SMART-TV|SmartTV/i.test(ua) ? 'Smart-TV' : /Linux/.test(ua) ? 'Linux' : null
  return [browser, os].filter(Boolean).join(' · ') || ua.slice(0, 40)
}

/** Which actions make sense for a row — the same rules the server enforces. */
function canDo(row: AccessRequestRow, action: AccessAction): boolean {
  if (action === 'approve') return row.status === 'pending' && row.kind === 'webapp'
  if (action === 'deny') return row.status === 'pending'
  return row.status === 'approved'
}

function AccessTab({ onLocked }: { onLocked: () => void }) {
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null)
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const { data, error } = useQuery({
    queryKey: ['admin', 'access-requests'],
    queryFn: listAccessRequests,
    refetchInterval: 5000,
  })

  useEffect(() => {
    if (error instanceof ApiError && error.status === 401) onLocked()
  }, [error, onLocked])

  const rows = data?.requests ?? []
  const currentId = data?.current_session_id

  // Drop selections whose row disappeared or can no longer be acted on
  // (e.g. decided in the terminal meanwhile) on every poll.
  useEffect(() => {
    setSelected((prev) => {
      const actionable = new Set(rows.filter((r) => r.status === 'pending' || r.status === 'approved').map((r) => r.id))
      const next = new Set([...prev].filter((id) => actionable.has(id)))
      return next.size === prev.size ? prev : next
    })
  }, [rows])

  const toggle = (id: number) =>
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  const selectAll = (ids: number[]) =>
    setSelected((prev) => {
      const allIn = ids.every((id) => prev.has(id))
      const next = new Set(prev)
      ids.forEach((id) => (allIn ? next.delete(id) : next.add(id)))
      return next
    })

  const run = async (targets: AccessRequestRow[], action: AccessAction) => {
    const applicable = targets.filter((r) => canDo(r, action))
    if (!applicable.length) return
    const hitsSelf = action === 'revoke' && applicable.some((r) => r.id === currentId)
    if (hitsSelf && !window.confirm('Darunter ist deine aktuelle Admin-Sitzung. Wirklich widerrufen?')) return
    if (applicable.length > 1 && !hitsSelf && action !== 'approve') {
      if (!window.confirm(`${applicable.length} Einträge ${ACTION_DONE[action]}?`)) return
    }
    setBusy(true)
    setMessage(null)
    try {
      const result = await bulkDecideAccessRequests(applicable.map((r) => r.id), action)
      const skipped = targets.length - applicable.length
      const parts = [`${result.done.length} ${ACTION_DONE[action]}`]
      if (skipped) parts.push(`${skipped} übersprungen (passt nicht zum Status)`)
      if (result.failed.length) parts.push(`${result.failed.length} fehlgeschlagen: ${result.failed.map((f) => `#${f.id} ${f.error}`).join('; ')}`)
      setMessage({ text: parts.join(' · '), error: result.failed.length > 0 })
      setSelected(new Set())
      if (hitsSelf && result.done.includes(currentId as number)) {
        onLocked()
        return
      }
      await queryClient.invalidateQueries({ queryKey: ['admin', 'access-requests'] })
    } catch (err) {
      setMessage({ text: errorText(err), error: true })
    } finally {
      setBusy(false)
    }
  }

  const pending = rows.filter((r) => r.status === 'pending')
  const others = rows.filter((r) => r.status !== 'pending')
  const selectedRows = rows.filter((r) => selected.has(r.id))
  const count = (action: AccessAction) => selectedRows.filter((r) => canDo(r, action)).length

  const renderRow = (row: AccessRequestRow) => {
    const actionable = row.status === 'pending' || row.status === 'approved'
    return (
      <div
        key={row.id}
        className={'admin-row' + (row.status === 'pending' ? ' admin-row--pending' : '') + (selected.has(row.id) ? ' admin-row--selected' : '')}
      >
        <label className={'admin-check' + (actionable ? '' : ' admin-check--off')}>
          <input type="checkbox" disabled={!actionable} checked={selected.has(row.id)} onChange={() => toggle(row.id)} />
        </label>
        <div className="admin-row__main">
          <div className="admin-row__title">
            <span className={'admin-badge admin-badge--' + row.kind}>{row.kind === 'admin' ? 'Admin' : 'Web-App'}</span>
            <span className="admin-row__id">#{row.id}</span>
            {row.code && <span className="admin-row__code">{row.code}</span>}
            <span className={'admin-status admin-status--' + row.status}>{STATUS_LABEL[row.status] ?? row.status}</span>
            {row.id === currentId && <span className="admin-status admin-status--self">Diese Sitzung</span>}
          </div>
          <div className="admin-row__meta" title={row.user_agent ?? ''}>
            {shortAgent(row.user_agent)} · {row.ip_address || 'IP unbekannt'} · angefragt {formatTime(row.requested_at)}
            {row.status === 'approved' && row.decided_at && <> · freigegeben {formatTime(row.decided_at)}</>}
          </div>
        </div>
        <div className="admin-row__actions">
          {canDo(row, 'approve') && (
            <button type="button" className="btn btn-primary btn-sm" disabled={busy} onClick={() => run([row], 'approve')}>
              Freigeben
            </button>
          )}
          {row.status === 'pending' && row.kind === 'admin' && (
            <span className="admin-hint">Freigabe nur im Terminal: <code>aniworld --web-approve {row.id}</code></span>
          )}
          {canDo(row, 'deny') && (
            <button type="button" className="filter btn-sm" disabled={busy} onClick={() => run([row], 'deny')}>
              Ablehnen
            </button>
          )}
          {canDo(row, 'revoke') && (
            <button type="button" className="filter btn-sm admin-danger" disabled={busy} onClick={() => run([row], 'revoke')}>
              Widerrufen
            </button>
          )}
        </div>
      </div>
    )
  }

  const section = (title: string, list: AccessRequestRow[], empty: string) => {
    const ids = list.filter((r) => r.status === 'pending' || r.status === 'approved').map((r) => r.id)
    const allIn = ids.length > 0 && ids.every((id) => selected.has(id))
    return (
      <>
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            {title}
          </div>
          {ids.length > 0 && (
            <button type="button" className="filter btn-sm" onClick={() => selectAll(ids)}>
              {allIn ? 'Auswahl aufheben' : 'Alle auswählen'}
            </button>
          )}
        </div>
        <div className="admin-list">{list.length ? list.map(renderRow) : <div className="admin-empty">{empty}</div>}</div>
      </>
    )
  }

  return (
    <>
      {message && <div className={'admin-message' + (message.error ? '' : ' admin-message--ok')}>{message.text}</div>}
      {selected.size > 0 && (
        <div className="admin-bulkbar">
          <span className="admin-bulkbar__count">{selected.size} ausgewählt</span>
          <button type="button" className="btn btn-primary btn-sm" disabled={busy || !count('approve')} onClick={() => run(selectedRows, 'approve')}>
            Freigeben ({count('approve')})
          </button>
          <button type="button" className="filter btn-sm" disabled={busy || !count('deny')} onClick={() => run(selectedRows, 'deny')}>
            Ablehnen ({count('deny')})
          </button>
          <button type="button" className="filter btn-sm admin-danger" disabled={busy || !count('revoke')} onClick={() => run(selectedRows, 'revoke')}>
            Widerrufen ({count('revoke')})
          </button>
          <button type="button" className="filter btn-sm" disabled={busy} onClick={() => setSelected(new Set())}>
            Auswahl aufheben
          </button>
          {selectedRows.some((r) => r.status === 'pending' && r.kind === 'admin') && (
            <span className="admin-hint">Admin-Anfragen werden beim Freigeben übersprungen – die gehen nur im Terminal.</span>
          )}
        </div>
      )}
      {section(`Offene Anfragen (${pending.length})`, pending, 'Keine offenen Anfragen.')}
      {section('Alle Geräte', others, 'Noch keine Geräte.')}
    </>
  )
}

// ── Watch history tab ───────────────────────────────────────────────────────

type HistoryView = 'series' | 'episodes'

const SERIES_SORTS: { value: SeriesSort; label: string }[] = [
  { value: 'recent', label: 'Zuletzt geschaut' },
  { value: 'latest_episode', label: 'Neueste Folge' },
  { value: 'title', label: 'Name A–Z' },
  { value: 'episodes', label: 'Meiste Folgen' },
]

const EPISODE_SORTS: { value: EpisodeSort; label: string }[] = [
  { value: 'recent', label: 'Zuletzt geschaut' },
  { value: 'oldest', label: 'Zuerst geschaut' },
  { value: 'episode_desc', label: 'Neueste Folge zuerst' },
  { value: 'episode', label: 'Folgen-Reihenfolge' },
  { value: 'title', label: 'Serie A–Z' },
]

function epLabel(season: number | undefined, episode: number | undefined): string {
  return `S${String(season ?? 0).padStart(2, '0')}E${String(episode ?? 0).padStart(2, '0')}`
}

function HistoryTab({ onLocked }: { onLocked: () => void }) {
  const queryClient = useQueryClient()
  const [view, setView] = useState<HistoryView>('series')
  const [profileId, setProfileId] = useState<number | undefined>(undefined)
  const [seriesFilter, setSeriesFilter] = useState<{ url: string; title: string } | null>(null)
  const [seriesSort, setSeriesSort] = useState<SeriesSort>('recent')
  const [episodeSort, setEpisodeSort] = useState<EpisodeSort>('recent')
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [limit, setLimit] = useState(HISTORY_PAGE)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search.trim()), 300)
    return () => clearTimeout(t)
  }, [search])

  useEffect(() => setLimit(HISTORY_PAGE), [view, profileId, debounced, seriesFilter, seriesSort, episodeSort])

  const profiles = useQuery({ queryKey: ['admin', 'profiles'], queryFn: listAdminProfiles })
  const seriesQuery = useQuery({
    queryKey: ['admin', 'history-series', profileId, debounced, seriesSort, limit],
    queryFn: () => getWatchHistorySeries({ profile_id: profileId, q: debounced || undefined, sort: seriesSort, limit, offset: 0 }),
    placeholderData: keepPreviousData,
    enabled: view === 'series',
  })
  const episodesQuery = useQuery({
    queryKey: ['admin', 'history', profileId, debounced, seriesFilter?.url, episodeSort, limit],
    queryFn: () =>
      getWatchHistory({
        profile_id: profileId,
        q: debounced || undefined,
        series_url: seriesFilter?.url,
        sort: episodeSort,
        limit,
        offset: 0,
      }),
    placeholderData: keepPreviousData,
    enabled: view === 'episodes',
  })

  useEffect(() => {
    const err = seriesQuery.error ?? episodesQuery.error ?? profiles.error
    if (err instanceof ApiError && err.status === 401) onLocked()
  }, [seriesQuery.error, episodesQuery.error, profiles.error, onLocked])

  const refresh = () => queryClient.invalidateQueries({ queryKey: ['admin'] })

  const openSeries = (s: HistorySeries) => {
    if (!s.series_url) return
    setProfileId(s.profile_id)
    setSeriesFilter({ url: s.series_url, title: s.series_title || s.series_url })
    setEpisodeSort('episode')
    setView('episodes')
  }

  const removeEntry = async (entry: HistoryEntry) => {
    const label = `${entry.series_title ?? 'Episode'} ${epLabel(entry.season, entry.episode_number)}`
    if (!window.confirm(`„${label}“ für ${entry.profile_name ?? 'dieses Profil'} als nicht gesehen markieren?`)) return
    setMessage(null)
    try {
      await deleteHistoryEntry(entry.id)
      await refresh()
    } catch (err) {
      setMessage(errorText(err))
    }
  }

  const removeSeries = async (profile: number, profileName: string | null, seriesUrl: string | null, title: string | null) => {
    if (!seriesUrl) return
    if (!window.confirm(`Den kompletten Verlauf von „${title ?? 'dieser Serie'}“ für ${profileName ?? 'dieses Profil'} löschen?`)) return
    setMessage(null)
    try {
      await deleteSeriesHistory(profile, seriesUrl)
      if (seriesFilter?.url === seriesUrl) setSeriesFilter(null)
      await refresh()
    } catch (err) {
      setMessage(errorText(err))
    }
  }

  const series = seriesQuery.data?.series ?? []
  const seriesTotal = seriesQuery.data?.total ?? 0
  const entries = episodesQuery.data?.entries ?? []
  const entriesTotal = episodesQuery.data?.total ?? 0
  const shown = view === 'series' ? series.length : entries.length
  const total = view === 'series' ? seriesTotal : entriesTotal
  const loading = view === 'series' ? seriesQuery.isLoading : episodesQuery.isLoading

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

      <div className="admin-toolbar">
        <div className="admin-segment">
          <button type="button" className={'filter btn-sm' + (view === 'series' ? ' on' : '')} onClick={() => setView('series')}>
            Serien
          </button>
          <button type="button" className={'filter btn-sm' + (view === 'episodes' ? ' on' : '')} onClick={() => setView('episodes')}>
            Episoden
          </button>
        </div>
        <input
          className="text-input admin-search"
          type="search"
          placeholder="Serie oder Episode suchen…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <label className="admin-sort">
          <span>Sortieren</span>
          {view === 'series' ? (
            <select value={seriesSort} onChange={(e) => setSeriesSort(e.target.value as SeriesSort)}>
              {SERIES_SORTS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          ) : (
            <select value={episodeSort} onChange={(e) => setEpisodeSort(e.target.value as EpisodeSort)}>
              {EPISODE_SORTS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          )}
        </label>
      </div>

      {view === 'episodes' && seriesFilter && (
        <div className="admin-filterchip-row">
          <button type="button" className="filter btn-sm on" onClick={() => setSeriesFilter(null)} title="Serienfilter entfernen">
            Serie: {seriesFilter.title} ✕
          </button>
        </div>
      )}

      <div className="admin-list">
        {view === 'series' &&
          series.map((s) => {
            const pct = s.episodes ? Math.round((s.completed / s.episodes) * 100) : 0
            return (
              <div key={`${s.profile_id}:${s.series_key}`} className="admin-row">
                <div className="admin-row__main">
                  <div className="admin-row__title">
                    <span className="admin-profile__dot" style={{ background: s.profile_color ?? 'var(--muted-2)' }} />
                    <span className="admin-row__profile">{s.profile_name ?? `Profil ${s.profile_id}`}</span>
                    <span className="admin-row__series">{s.series_title || s.series_key}</span>
                    <span className="admin-status admin-status--approved">{s.completed} / {s.episodes} gesehen</span>
                  </div>
                  <div className="admin-progress">
                    <div className="admin-progress__bar" style={{ width: `${pct}%` }} />
                  </div>
                  <div className="admin-row__meta">
                    Neueste Folge {epLabel(s.latest_season, s.latest_episode)} · zuletzt geschaut{' '}
                    {epLabel(s.last_season, s.last_episode)}
                    {s.last_episode_title && <> „{s.last_episode_title}“</>} am {formatTime(s.last_watched)}
                  </div>
                </div>
                <div className="admin-row__actions">
                  {s.series_url && (
                    <button type="button" className="btn btn-ghost btn-sm" onClick={() => openSeries(s)}>
                      Folgen anzeigen
                    </button>
                  )}
                  {s.series_url && (
                    <button
                      type="button"
                      className="filter btn-sm admin-danger"
                      onClick={() => removeSeries(s.profile_id, s.profile_name, s.series_url, s.series_title)}
                    >
                      Serie zurücksetzen
                    </button>
                  )}
                </div>
              </div>
            )
          })}

        {view === 'episodes' &&
          entries.map((e) => {
            const pct = e.duration_seconds > 0 ? Math.min(100, (e.position_seconds / e.duration_seconds) * 100) : 0
            return (
              <div key={e.id} className="admin-row">
                <div className="admin-row__main">
                  <div className="admin-row__title">
                    <span className="admin-profile__dot" style={{ background: e.profile_color ?? 'var(--muted-2)' }} />
                    <span className="admin-row__profile">{e.profile_name ?? `Profil ${e.profile_id}`}</span>
                    <span className="admin-row__series">{e.series_title || e.episode_url}</span>
                    <span className="admin-row__ep">{epLabel(e.season, e.episode_number)}</span>
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
                  {e.series_url && !seriesFilter && (
                    <button type="button" className="filter btn-sm" onClick={() => removeSeries(e.profile_id, e.profile_name, e.series_url, e.series_title)}>
                      Ganze Serie zurücksetzen
                    </button>
                  )}
                </div>
              </div>
            )
          })}

        {!loading && shown === 0 && <div className="admin-empty">Kein Verlauf gefunden.</div>}
      </div>
      {shown < total && (
        <button type="button" className="btn btn-ghost admin-more" onClick={() => setLimit((l) => l + HISTORY_PAGE)}>
          Mehr laden ({shown} von {total})
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
            {session.data && (
              <span className="admin-muted text-body-md">
                Dieser Browser ist dauerhaft freigegeben{session.data.approved_at && <> (seit {formatTime(session.data.approved_at)})</>}
              </span>
            )}
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
