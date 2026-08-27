// Port of app/lib/screens/web_access_screen.dart. Shown only on this web
// build — there is no username/password form here. A browser without a
// valid token asks the backend for access, and an admin has to approve it
// from the server terminal (`aniworld --web-requests` / `--web-approve
// <id>`). This screen just polls until that happens.
import { useCallback, useEffect, useRef, useState } from 'react'
import { pollAccess, requestAccess } from '../api/webappAuth'
import { setToken } from '../api/client'
import { useAuth } from '../context/AuthContext'
import { Icon } from '../components/layout/icons'
import './WebAccessPage.css'

const DEVICE_ID_KEY = 'rstv_device_id'
const POLL_INTERVAL_MS = 3000

type State = 'requesting' | 'pending' | 'denied' | 'error'

export function WebAccessPage() {
  const { refresh } = useAuth()
  const [state, setState] = useState<State>('requesting')
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const deviceIdRef = useRef<string | null>(null)
  // Guards against React StrictMode's dev-only double-invoke of this effect,
  // which would otherwise fire two concurrent request-access POSTs (a real
  // server-side side effect, not idempotent) before either resolves. Retry
  // clicks bypass this guard intentionally — it only protects the initial
  // automatic mount.
  const startedRef = useRef(false)

  const stopPolling = useCallback(() => {
    if (pollRef.current !== null) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  const checkStatus = useCallback(async () => {
    const deviceId = deviceIdRef.current
    if (!deviceId) return
    try {
      const result = await pollAccess(deviceId)
      if (result.status === 'approved' && result.token) {
        stopPolling()
        localStorage.removeItem(DEVICE_ID_KEY)
        setToken(result.token)
        await refresh()
      } else if (result.status === 'denied' || result.status === 'revoked') {
        stopPolling()
        localStorage.removeItem(DEVICE_ID_KEY)
        setState('denied')
      }
      // 'pending' — keep polling.
    } catch {
      // Transient network error while polling — keep trying, matching the
      // Flutter screen's behavior exactly.
    }
  }, [refresh, stopPolling])

  const start = useCallback(async () => {
    setState('requesting')
    let deviceId = localStorage.getItem(DEVICE_ID_KEY)
    if (!deviceId) {
      try {
        const result = await requestAccess()
        deviceId = result.device_id
        localStorage.setItem(DEVICE_ID_KEY, deviceId)
      } catch {
        setState('error')
        return
      }
    }
    deviceIdRef.current = deviceId
    setState('pending')
    pollRef.current = setInterval(checkStatus, POLL_INTERVAL_MS)
    checkStatus()
  }, [checkStatus])

  useEffect(() => {
    if (!startedRef.current) {
      startedRef.current = true
      start()
    }
    return stopPolling
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="web-access">
      <div className="web-access__card">
        <div className="web-access__brand">
          <div className="brand-mark">
            <Icon name="play" w={22} />
          </div>
          <div className="brand-name">
            Red<b>Stream</b>
          </div>
        </div>
        {state === 'requesting' && <div className="spinner" />}
        {state === 'pending' && (
          <>
            <div className="spinner" />
            <h1 className="text-title-lg">Zugriff angefragt</h1>
            <p className="text-body-lg web-access__text">
              Ein Administrator muss diesen Browser auf dem Server freigeben, bevor es weitergeht.
            </p>
            <pre className="web-access__code">
              aniworld --web-requests{'\n'}aniworld --web-approve &lt;ID&gt;
            </pre>
          </>
        )}
        {state === 'denied' && (
          <>
            <div className="web-access__icon web-access__icon--error">✕</div>
            <h1 className="text-title-lg">Zugriff verweigert</h1>
            <p className="text-body-lg web-access__text">
              Der Administrator hat diese Anfrage abgelehnt oder widerrufen.
            </p>
            <button type="button" className="btn btn-primary" onClick={start}>
              Erneut anfragen
            </button>
          </>
        )}
        {state === 'error' && (
          <>
            <div className="web-access__icon web-access__icon--error">!</div>
            <h1 className="text-title-lg">Verbindungsfehler</h1>
            <p className="text-body-lg web-access__text">Der Server konnte nicht erreicht werden.</p>
            <button type="button" className="btn btn-primary" onClick={start}>
              Erneut versuchen
            </button>
          </>
        )}
      </div>
    </div>
  )
}
