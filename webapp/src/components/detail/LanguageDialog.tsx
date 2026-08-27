import { Modal } from '../common/Modal'

// Fixed list, verified against app/lib/screens/detail_screen.dart's
// _LanguageOverrideDialog (kAllLanguages).
const LANGUAGES = ['German Dub', 'German Sub', 'English Dub', 'English Sub']

export interface LanguageDialogProps {
  current: string | null
  onSelect: (language: string) => void
  onClear: () => void
  onClose: () => void
}

export function LanguageDialog({ current, onSelect, onClear, onClose }: LanguageDialogProps) {
  return (
    <Modal title="Sprache" onClose={onClose}>
      <div className="language-dialog__list">
        {LANGUAGES.map((lang) => (
          <button
            key={lang}
            type="button"
            className={`filter${current === lang ? ' on' : ''}`}
            onClick={() => onSelect(lang)}
          >
            {lang}
          </button>
        ))}
        {current && (
          <button type="button" className="filter" onClick={onClear}>
            Zurücksetzen
          </button>
        )}
      </div>
    </Modal>
  )
}
