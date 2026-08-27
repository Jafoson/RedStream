// Route-gating skeleton mirroring app/lib/main.dart's _resolveInitScreen:
// bootstrapping -> web-access (device approval) -> needs-profile -> ready.
import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './context/AuthContext'
import { WebAccessPage } from './pages/WebAccessPage'
import { ProfileSelectPage } from './pages/ProfileSelectPage'
import { Shell } from './components/layout/Shell'
import { DownloadPlayPage } from './pages/DownloadPlayPage'
import { DetailPage } from './pages/DetailPage'
import { TvStage } from './tv/TvStage'
import { FocusProvider } from './tv/FocusEngine'
import { ToastProvider } from './tv/ToastContext'

// hls.js is ~700kB — code-split so it's only fetched when the player route
// is actually hit (same pattern as react/'s WatchPage lazy-import).
const PlayerPage = lazy(() => import('./pages/PlayerPage').then((m) => ({ default: m.PlayerPage })))

function AppBody() {
  const { state } = useAuth()

  if (state === 'bootstrapping') {
    return (
      <div className="app-loading">
        <div className="spinner" />
      </div>
    )
  }

  if (state === 'web-access') return <WebAccessPage />
  if (state === 'needs-profile') return <ProfileSelectPage />

  return (
    <Routes>
      <Route path="/" element={<Shell />} />
      <Route
        path="/watch"
        element={
          <Suspense
            fallback={
              <div className="app-loading">
                <div className="spinner" />
              </div>
            }
          >
            <PlayerPage />
          </Suspense>
        }
      />
      <Route path="/download-play" element={<DownloadPlayPage />} />
      <Route path="/detail" element={<DetailPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default function App() {
  return (
    <TvStage>
      <FocusProvider>
        <ToastProvider>
          <AppBody />
        </ToastProvider>
      </FocusProvider>
    </TvStage>
  )
}
