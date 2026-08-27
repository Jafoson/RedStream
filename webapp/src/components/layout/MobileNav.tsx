// Touch-primary replacement for the Sidebar below the 1024px breakpoint
// (styles/breakpoints.ts's SIDEBAR_BREAKPOINT) — a fixed bottom bar, always
// mounted but CSS-hidden above that width (see MobileNav.css), so there's no
// remount/re-registration churn crossing the breakpoint.
//
// Deliberately NOT wired into FocusContext/region:'sidebar' at all — no
// onMouseEnter, no setFocus(), no is-foc class. A touch tap fires onClick
// directly; there's no D-pad keydown listener on a touchscreen to feed
// Left/Right sidebar semantics to, so giving these items focus cells would
// add machinery a touch user can never actually trigger.
//
// Shows every tab as a horizontally-scrollable strip rather than a curated
// fixed 5 — avoids inventing a new "Mehr" overflow pattern and a subjective
// which-tabs-survive call; everything stays one tap away.
import { SIDEBAR_ITEMS, type NavTab } from '../../navigation/tabs'
import { Icon } from './icons'
import './MobileNav.css'

export interface MobileNavProps {
  active: NavTab
  onSelect: (tab: NavTab) => void
  onProfileSwitch: () => void
}

export function MobileNav({ active, onSelect, onProfileSwitch }: MobileNavProps) {
  function activate(item: (typeof SIDEBAR_ITEMS)[number]) {
    if (item.tab === 'profile-switch') onProfileSwitch()
    else onSelect(item.tab)
  }

  return (
    <nav className="mobile-nav">
      {SIDEBAR_ITEMS.map((item) => (
        <button
          key={item.tab}
          type="button"
          className={'mobile-nav__item' + (item.tab === active ? ' active' : '')}
          onClick={() => activate(item)}
        >
          <Icon name={item.icon} w={22} />
          <span>{item.label}</span>
        </button>
      ))}
    </nav>
  )
}
