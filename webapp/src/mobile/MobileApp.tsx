// The phone view (see view.ts): its own routes and chrome — bottom tabs,
// remote bar for the selected TV, target sheet — looking like the native
// iOS/Android apps. Shares the API layer, auth and cast protocol with the
// TV layout.
import { Navigate, Route, Routes, useLocation, useSearchParams } from 'react-router-dom'
import { DownloadPlayPage } from '../pages/DownloadPlayPage'
import { PlayerPage } from '../pages/PlayerPage'
import { CastProvider } from './CastContext'
import { CastSheet, M_TABS, MToastProvider, RemoteBar, TabBar, type MTab } from './components'
import { BrowseScreen } from './screens/BrowseScreen'
import { DetailScreen } from './screens/DetailScreen'
import { HomeScreen } from './screens/HomeScreen'
import { MoreScreen } from './screens/MoreScreen'
import { PlayerScreen } from './screens/PlayerScreen'
import { SearchScreen } from './screens/SearchScreen'
import { WatchlistScreen } from './screens/WatchlistScreen'
import './mobile.css'

function Tabs() {
  const [params] = useSearchParams()
  const raw = params.get('tab')
  const tab: MTab = M_TABS.some((t) => t.tab === raw) ? (raw as MTab) : 'start'
  switch (tab) {
    case 'entdecken':
      return <BrowseScreen />
    case 'suche':
      return <SearchScreen />
    case 'liste':
      return <WatchlistScreen />
    case 'mehr':
      return <MoreScreen />
    default:
      return <HomeScreen />
  }
}

function Chrome() {
  const location = useLocation()
  const [params] = useSearchParams()
  const inPlayer = ['/abspielen', '/watch', '/download-play'].includes(location.pathname)
  const tab = location.pathname === '/' ? ((params.get('tab') as MTab) || 'start') : null

  return (
    <div className={'m-app' + (inPlayer ? ' m-app--player' : '')}>
      <main className="m-main" key={location.pathname + location.search}>
        <Routes>
          <Route path="/" element={<Tabs />} />
          <Route path="/serie" element={<DetailScreen />} />
          <Route path="/abspielen" element={<PlayerScreen />} />
          {/* When this phone is itself a cast target (Mehr → Als Bildschirm verfügbar). */}
          <Route path="/download-play" element={<DownloadPlayPage />} />
          <Route path="/watch" element={<PlayerPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      {!inPlayer && (
        <footer className="m-bottom">
          <RemoteBar />
          <TabBar active={tab} />
        </footer>
      )}
      <CastSheet />
    </div>
  )
}

export function MobileApp() {
  return (
    <CastProvider>
      <MToastProvider>
        <Chrome />
      </MToastProvider>
    </CastProvider>
  )
}
