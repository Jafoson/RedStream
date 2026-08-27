import { useEffect, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import './Modal.css'

export interface ModalProps {
  title: string
  onClose: () => void
  children: ReactNode
}

export function Modal({ title, onClose, children }: ModalProps) {
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [onClose])

  // Rendered via a portal straight to <body> — the sidebar's hover-driven
  // width transition and the player's fixed-position overlay both create CSS
  // containing blocks for descendant `position: fixed` elements, which would
  // otherwise box a nested modal into the wrong ancestor's bounds (the same
  // bug class the /react dashboard's Modal.tsx hit and fixed the same way).
  return createPortal(
    <div
      className="modal-overlay"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div className="modal panel">
        <div className="modal__header">
          <h3 className="text-title-md modal__title">{title}</h3>
          <button type="button" className="modal__close" onClick={onClose} aria-label="Schließen">
            ×
          </button>
        </div>
        <div className="modal__body">{children}</div>
      </div>
    </div>,
    document.body,
  )
}
