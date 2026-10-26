// "Als App installieren": banner on Start (dismissible, comes back after two
// weeks) and a card under Mehr, both gone once RedStream runs installed.
import { dismissInstallHint, promptInstall, useInstallState, type InstallState } from './install'
import { MIcon } from './icons'

function Steps({ state }: { state: InstallState }) {
  if (state.platform === 'ios') {
    return (
      <ol className="m-install__steps">
        <li>
          Tippe in Safari unten auf <MIcon name="share" size={18} className="m-install__inline" /> <strong>Teilen</strong>
        </li>
        <li>
          Wähle <MIcon name="addBox" size={18} className="m-install__inline" /> <strong>Zum Home-Bildschirm</strong>
        </li>
      </ol>
    )
  }
  return (
    <ol className="m-install__steps">
      <li>
        Öffne im Browser das Menü <strong>⋮</strong>
      </li>
      <li>
        Wähle <strong>App installieren</strong> bzw. <strong>Zum Startbildschirm hinzufügen</strong>
      </li>
    </ol>
  )
}

function Body({ state }: { state: InstallState }) {
  return (
    <>
      <p className="m-install__text">
        RedStream als App auf dem Home-Bildschirm: startet im Vollbild, ohne Browserleiste, mit eigenem Symbol.
      </p>
      {state.canPrompt ? (
        <button type="button" className="m-btn m-btn--primary" onClick={() => promptInstall()}>
          <MIcon name="addBox" size={20} />
          Installieren
        </button>
      ) : (
        <Steps state={state} />
      )}
    </>
  )
}

/** Dismissible banner at the top of Start. */
export function InstallBanner() {
  const state = useInstallState()
  if (!state.showHint) return null
  return (
    <section className="m-install" aria-label="Als App installieren">
      <div className="m-install__head">
        <img src="/apple-touch-icon.png" alt="" className="m-install__icon" />
        <strong>Als App installieren</strong>
        <button type="button" className="m-icon-btn m-install__close" aria-label="Hinweis schließen" onClick={dismissInstallHint}>
          <MIcon name="close" size={20} />
        </button>
      </div>
      <Body state={state} />
    </section>
  )
}

/** Card under Mehr (always there until installed). */
export function InstallCard() {
  const state = useInstallState()
  if (state.installed) return null
  return (
    <section className="m-cardbox">
      <h3>Als App installieren</h3>
      <Body state={state} />
    </section>
  )
}
