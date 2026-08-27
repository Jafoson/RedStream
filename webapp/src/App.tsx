// Route-gating skeleton mirroring app/lib/main.dart's _resolveInitScreen:
// bootstrapping -> web-access (device approval) -> needs-profile -> ready.
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
import { PlayerPage } from './pages/PlayerPage'
// Deliberately a plain eager import, not React.lazy() — hls.js's ~700kB is
// still code-split (see HlsPlayer.tsx's own dynamic import('hls.js')), but
// wrapping this whole route in Suspense measurably delayed React's commit
// for the page itself by ~300ms, even once the chunk was already cached
// (React schedules a lazy-loaded subtree's updates through a lower-priority
// "retry" lane) — see HlsPlayer.tsx's comment for the full story and the
// before/after measurement.

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
      <Route path="/watch" element={<PlayerPage />} />
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
