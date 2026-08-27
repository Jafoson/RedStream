// Full-viewport stage — was previously a fixed 1920x1080 canvas scaled to
// fit the window, which letterboxed (black bars) on any browser window that
// wasn't exactly 16:9. Now #tv just fills the real window at its native
// size, so the app always uses the full width/height like a normal
// responsive web page.
import type { ReactNode } from 'react'
import './TvStage.css'

export function TvStage({ children }: { children: ReactNode }) {
  return (
    <div id="stage-root">
      <div id="tv">
        <div id="ambient" />
        {children}
      </div>
    </div>
  )
}
