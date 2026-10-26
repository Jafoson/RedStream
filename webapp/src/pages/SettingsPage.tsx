// Only the sections relevant to this web build — "Speicher" (storage usage)
// and "Verbindung" (revoke device access). The native-only "Server"/"Updates"
// sections from app/lib/screens/settings_screen.dart don't apply here: this
// app is always same-origin and has no self-update mechanism.
import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getStorageStats } from '../api/library'
import { isDirectStreamEnabled, setDirectStreamEnabled } from '../api/live'
import { getScreenName, isScreenEnabled, setScreenEnabled, setScreenName } from '../cast/screenSettings'
import { useAuth } from '../context/AuthContext'
import { useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import { useIsTv } from '../tv/useIsTv'
import { getTvOverride, setTvOverride, detectTvFromUA } from '../tv/detectTv'
import { isPhoneDevice, setViewOverride } from '../mobile/view'
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
  const navigate = useNavigate()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const { data } = useQuery({ queryKey: ['storage-stats'], queryFn: getStorageStats })
  const isTv = useIsTv()
  const [directStream, setDirectStream] = useState(isDirectStreamEnabled)

  const [screenOn, setScreenOn] = useState(isScreenEnabled)
  const [screenName, setScreenNameState] = useState(getScreenName)
  const nameInputRef = useRef<HTMLInputElement>(null)

  const toggleScreen = () =>
    setScreenOn((on) => {
      setScreenEnabled(!on)
      return !on
    })

  const toggleDirectStream = () =>
    setDirectStream((on) => {
      setDirectStreamEnabled(!on)
      return !on
    })

  // Only on a phone that was switched to this (TV) layout: the way back.
  const [phone] = useState(isPhoneDevice)

  useRegisterNav(
    phone ? [1, 1, 1, 1, 1, 1, 1] : [1, 1, 1, 1, 1, 1],
    (row) => {
      if (row === 0) cycleTvOverride()
      else if (row === 1) toggleDirectStream()
      else if (row === 2) toggleScreen()
      else if (row === 3) nameInputRef.current?.focus()
      else if (row === 4) logout()
      else if (row === 5) navigate('/verwaltung')
      else if (row === 6) setViewOverride(null)
    },
    [],
  )
  useAutoScrollRow(scrollerRef)
  const tvToggleFocused = focus.region === 'content' && focus.row === 0
  const streamFocused = focus.region === 'content' && focus.row === 1
  const screenFocused = focus.region === 'content' && focus.row === 2
  const nameFocused = focus.region === 'content' && focus.row === 3
  const revokeFocused = focus.region === 'content' && focus.row === 4
  const adminFocused = focus.region === 'content' && focus.row === 5

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
          {phone && (
            <button
              type="button"
              className={'btn btn-ghost row-anchor' + (focus.region === 'content' && focus.row === 6 ? ' is-foc' : '')}
              data-row="6"
              onClick={() => setViewOverride(null)}
            >
              Zur Handy-Ansicht wechseln
            </button>
          )}
        </div>
      </section>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Wiedergabe
          </div>
        </div>
        <div className="panel settings-section">
          <p className="text-body-md settings-section__hint">
            Noch nicht heruntergeladene Folgen starten sofort und werden direkt vom Anbieter gestreamt,
            statt erst komplett heruntergeladen zu werden. Klappt das bei einer Folge nicht, wird sie
            wie bisher heruntergeladen.
          </p>
          <button
            type="button"
            className={'btn btn-ghost row-anchor' + (directStream ? ' on' : '') + (streamFocused ? ' is-foc' : '')}
            data-row="1"
            onMouseEnter={(e) => setFocus({ region: 'content', row: 1, col: 0 }, e)}
            onClick={toggleDirectStream}
          >
            Direkt streamen: {directStream ? 'An' : 'Aus'}
          </button>
        </div>
      </section>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Bildschirm
          </div>
        </div>
        <div className="panel settings-section">
          <p className="text-body-md settings-section__hint">
            Ist das an, taucht dieser Browser in der RedStream-App unter „Auf TV abspielen“ auf und
            die App kann hier Folgen starten, pausieren und spulen.
          </p>
          <button
            type="button"
            className={'btn btn-ghost row-anchor' + (screenOn ? ' on' : '') + (screenFocused ? ' is-foc' : '')}
            data-row="2"
            onMouseEnter={(e) => setFocus({ region: 'content', row: 2, col: 0 }, e)}
            onClick={toggleScreen}
          >
            Als Bildschirm verfügbar: {screenOn ? 'An' : 'Aus'}
          </button>
          <label className="settings-field row-anchor" data-row="3">
            <span className="text-body-md">Name in der App</span>
            <input
              ref={nameInputRef}
              className={'text-input' + (nameFocused ? ' is-foc' : '')}
              value={screenName}
              maxLength={60}
              placeholder="z. B. TV Wohnzimmer"
              onMouseEnter={(e) => setFocus({ region: 'content', row: 3, col: 0 }, e)}
              onChange={(e) => setScreenNameState(e.target.value)}
              onBlur={() => {
                setScreenName(screenName)
                setScreenNameState(getScreenName())
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') e.currentTarget.blur()
              }}
            />
          </label>
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
          <button type="button" className={'filter row-anchor' + (revokeFocused ? ' is-foc' : '')} data-row="4" onClick={logout}>
            Zugriff widerrufen
          </button>
        </div>
      </section>

      <section className="settings-block">
        <div className="section-head">
          <div className="section-title">
            <span className="bar" />
            Verwaltung
          </div>
        </div>
        <div className="panel settings-section">
          <p className="text-body-md settings-section__hint">
            Geräte freigeben oder sperren und den Verlauf aller Profile ansehen. Braucht eine
            zusätzliche Freigabe im Server-Terminal.
          </p>
          <button
            type="button"
            className={'filter row-anchor' + (adminFocused ? ' is-foc' : '')}
            data-row="5"
            onMouseEnter={(e) => setFocus({ region: 'content', row: 5, col: 0 }, e)}
            onClick={() => navigate('/verwaltung')}
          >
            Admin-Bereich öffnen
          </button>
        </div>
      </section>
    </div>
  )
}
