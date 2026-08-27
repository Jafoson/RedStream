// Horizontal rail. Scrolling is native (mouse wheel — including
// shift+wheel/trackpad for horizontal — and drag), so it behaves like any
// other scrollable row on desktop. Only deliberate keyboard/D-pad navigation
// programmatically scrolls the focused card into view — mouse hover updates
// which card is "focused" (for click/Enter semantics and the accent glow)
// but must never itself yank the rail around.
import { useEffect, useRef, type ReactNode } from 'react'
import { useFocusEngine } from '../../tv/FocusEngine'
import './Rail.css'

export interface RailProps {
  title: string
  rowIndex: number
  itemCount: number
  children: ReactNode
}

export function Rail({ title, rowIndex, itemCount, children }: RailProps) {
  const { focus } = useFocusEngine()
  const trackRef = useRef<HTMLDivElement>(null)

  const rowFocused = focus.region === 'content' && focus.row === rowIndex
  const col = rowFocused ? focus.col : null

  useEffect(() => {
    if (col == null || focus.origin !== 'keyboard') return
    const track = trackRef.current
    const card = track?.children[col] as HTMLElement | undefined
    card?.scrollIntoView({ behavior: 'smooth', inline: 'nearest', block: 'nearest' })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [col, focus.origin, itemCount])

  return (
    <div className="section row-anchor" data-row={rowIndex}>
      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          {title}
        </div>
      </div>
      <div className="rail" ref={trackRef}>
        {children}
      </div>
    </div>
  )
}
