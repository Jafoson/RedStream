// Only the sections relevant to this web build — "Speicher" (storage usage)
// and "Verbindung" (revoke device access). The native-only "Server"/"Updates"
// sections from app/lib/screens/settings_screen.dart don't apply here: this
// app is always same-origin and has no self-update mechanism.
import { useRef } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getStorageStats } from '../api/library'
import { useAuth } from '../context/AuthContext'
import { useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useIsTv } from '../tv/useIsTv'
import { getTvOverride, setTvOverride, detectTvFromUA } from '../tv/detectTv'
import './SettingsPage.css'

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 GB'
  const gb = bytes / 1024 ** 3
  return gb >= 1 ? `${gb.toFixed(1)} GB` : `${(bytes / 1024 ** 2).toFixed(0)} MB`
}

// Auto -> An -> Aus -> Auto, one button rather than two separate on/off
// buttons — matches the codebase's existing single-toggle idiom (watchlist/
// autosync buttons in HeroSection.tsx) more closely than adding a new
// two-button control just for this.
function cycleTvOverride() {
  const current = getTvOverride()
  const next = current === null ? 'on' : current === 'on' ? 'off' : null
  setTvOverride(next)
}

function tvModeLabel(): string {
  const override = getTvOverride()
  if (override === 'on') return 'Manuell aktiviert'
  if (override === 'off') return 'Manuell deaktiviert'
  return detectTvFromUA(navigator.userAgent) ? 'Automatisch erkannt' : 'Automatisch (nicht erkannt)'
}

export function SettingsPage() {
  const { logout } = useAuth()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const { data } = useQuery({ queryKey: ['storage-stats'], queryFn: getStorageStats })
  const isTv = useIsTv()

  useRegisterNav(
    [2],
    (row) => {
      if (row === 0) cycleTvOverride()
      else if (row === 1) logout()
    },
    [],
  )
  useAutoScrollRow(scrollerRef)
  const tvToggleFocused = focus.region === 'content' && focus.row === 0
  const revokeFocused = focus.region === 'content' && focus.row === 1

  return (
    <div className="scroller" ref={scrollerRef}>
      <div className="grid-head">
        <div className="grid-eyebrow">REDSTREAM</div>
        <h1 className="grid-h1">Einstellungen</h1>
      </div>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Speicher
          </div>
        </div>
        <div className="panel settings-section">
          {data?.roots.map((root) => (
            <div key={root.label} className="storage-banner__row">
              <span className="text-body-md">{root.label}</span>
              <span className="text-body-md">
                RedStream: {formatBytes(root.downloads_bytes)} · frei {formatBytes(root.disk_free_bytes)}
              </span>
            </div>
          ))}
        </div>
      </section>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Anzeige
          </div>
        </div>
        <div className="panel settings-section">
          <p className="text-body-md settings-section__hint">
            TV-Modus zeigt die Serien/Anime/Filme-Übersicht mit größeren Kacheln und
            weniger Spalten, optimiert für den Fernseher aus ein paar Metern Entfernung.
          </p>
          <button
            type="button"
            className={'btn btn-ghost row-anchor' + (isTv ? ' on' : '') + (tvToggleFocused ? ' is-foc' : '')}
            data-row="0"
            onMouseEnter={(e) => setFocus({ region: 'content', row: 0, col: 0 }, e)}
            onClick={cycleTvOverride}
          >
            TV-Modus: {isTv ? 'An' : 'Aus'} ({tvModeLabel()})
          </button>
        </div>
      </section>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Verbindung
          </div>
        </div>
        <div className="panel settings-section">
          <p className="text-body-md settings-section__hint">
            Dieser Browser ist über die Geräte-Freigabe mit dem Server verbunden.
          </p>
          <button type="button" className={'filter row-anchor' + (revokeFocused ? ' is-foc' : '')} data-row="1" onClick={logout}>
            Zugriff widerrufen
          </button>
        </div>
      </section>
    </div>
  )
}
