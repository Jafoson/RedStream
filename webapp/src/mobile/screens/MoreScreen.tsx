import { useState, type ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getProfiles } from '../../api/profiles'
import { getActiveProfileId } from '../../api/client'
import { getScreenName, isScreenEnabled, setScreenEnabled, setScreenName } from '../../cast/screenSettings'
import { useAuth } from '../../context/AuthContext'
import { useCast } from '../CastContext'
import { TopBar } from '../components'
import { setViewOverride } from '../view'

export function MoreScreen() {
  const { switchProfile, logout } = useAuth()
  const cast = useCast()
  const profiles = useQuery({ queryKey: ['m-profiles'], queryFn: getProfiles })
  const profileName = profiles.data?.find((p) => p.id === getActiveProfileId())?.name ?? '—'
  const [screenOn, setScreenOn] = useState(isScreenEnabled)
  const [screenName, setName] = useState(getScreenName)

  return (
    <>
      <TopBar title="Mehr" />
      <div className="m-scroll m-more">
        <Card title="Profil">
          <div className="m-more__value">{profileName}</div>
          <button type="button" className="m-btn m-btn--outline" onClick={switchProfile}>
            Profil wechseln
          </button>
        </Card>
        <Card title="Abspielen auf">
          <div className="m-more__value">{cast.target?.name ?? 'Dieses Handy'}</div>
          <p className="m-muted">
            Wähle einen Fernseher, auf dem RedStream im Browser offen ist – dann starten Folgen dort statt auf dem Handy.
          </p>
          <button type="button" className="m-btn m-btn--primary" onClick={() => cast.setSheetOpen(true)}>
            Gerät wählen
          </button>
        </Card>
        <Card title="Dieses Handy als Bildschirm">
          <p className="m-muted">
            Ist das an, kann ein anderes Gerät Folgen auf diesem Handy starten (wie bei einem Fernseher).
          </p>
          <button
            type="button"
            className="m-btn m-btn--outline"
            onClick={() => {
              setScreenEnabled(!screenOn)
              setScreenOn(!screenOn)
            }}
          >
            Als Bildschirm verfügbar: {screenOn ? 'An' : 'Aus'}
          </button>
          {screenOn && (
            <input
              className="m-input"
              value={screenName}
              maxLength={60}
              placeholder="Name"
              onChange={(e) => setName(e.target.value)}
              onBlur={() => {
                setScreenName(screenName)
                setName(getScreenName())
              }}
            />
          )}
        </Card>
        <Card title="Ansicht">
          <p className="m-muted">Die große Ansicht wie am Fernseher, mit Seitenleiste.</p>
          <button type="button" className="m-btn m-btn--outline" onClick={() => setViewOverride('classic')}>
            Zur TV-Ansicht wechseln
          </button>
        </Card>
        <Card title="Verbindung">
          <p className="m-muted">Dieser Browser ist über die Geräte-Freigabe mit dem Server verbunden.</p>
          <button type="button" className="m-btn m-btn--outline" onClick={logout}>
            Zugriff widerrufen
          </button>
        </Card>
        <p className="m-muted m-more__footer">RedStream im Browser · Tipp: Über „Zum Home-Bildschirm“ wird daraus eine App.</p>
      </div>
    </>
  )
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="m-cardbox">
      <h3>{title}</h3>
      {children}
    </section>
  )
}
