import { useState } from 'react'
import { SIDEBAR_ITEMS, type NavTab } from '../../navigation/tabs'
import { useFocusEngine } from '../../tv/FocusEngine'
import { Icon } from './icons'
import './Sidebar.css'

export interface SidebarProps {
  active: NavTab
  onSelect: (tab: NavTab) => void
  onProfileSwitch: () => void
}

export function Sidebar({ active, onSelect, onProfileSwitch }: SidebarProps) {
  const { focus, setFocus } = useFocusEngine()
  const [hovered, setHovered] = useState(false)
  // Expanded whenever it has D-pad/keyboard focus, or the mouse is over it —
  // matches the native Flutter app's RsSidebar (collapsed icon rail that
  // only expands on focus/hover).
  const expanded = focus.region === 'sidebar' || hovered

  function activate(item: (typeof SIDEBAR_ITEMS)[number]) {
    if (item.tab === 'profile-switch') onProfileSwitch()
    else onSelect(item.tab)
  }

  function renderGroup(group: (typeof SIDEBAR_ITEMS)[number]['group']) {
    return SIDEBAR_ITEMS.map((item, idx) => {
      if (item.group !== group) return null
      const isFoc = focus.region === 'sidebar' && focus.row === idx
      const isActive = item.tab === active
      return (
        <div
          key={item.tab}
          className={'navitem' + (isActive ? ' active' : '') + (isFoc ? ' is-foc' : '')}
          onMouseEnter={(e) => setFocus({ region: 'sidebar', row: idx, col: 0 }, e)}
          onClick={() => activate(item)}
        >
          <span className="nav-ic">
            <Icon name={item.icon} w={22} />
          </span>
          {expanded && <span className="navitem__label">{item.label}</span>}
        </div>
      )
    })
  }

  return (
    <aside
      className={'sidebar' + (expanded ? ' sidebar--expanded' : '')}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div className="brand">
        <div className="brand-mark">
          <Icon name="play" w={22} />
        </div>
        {expanded && (
          <div className="brand-name">
            Red<b>Stream</b>
          </div>
        )}
      </div>
      <div className="nav-group-label">{expanded && 'MENÜ'}</div>
      <div className="navlist">{renderGroup('menu')}</div>
      <div className="nav-group-label">{expanded && 'BIBLIOTHEK'}</div>
      <div className="navlist">{renderGroup('library')}</div>
      <div className="sidebar-spacer" />
      <div className="navlist">{renderGroup('general')}</div>
      <div className="navlist">{renderGroup('profile')}</div>
    </aside>
  )
}
