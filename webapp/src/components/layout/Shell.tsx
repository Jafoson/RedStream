import { useCallback, useEffect, useRef } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Sidebar } from './Sidebar'
import { MobileNav } from './MobileNav'
import { DEFAULT_TAB, isNavTab, SIDEBAR_ITEMS, type NavTab } from '../../navigation/tabs'
import { useFocusEngine } from '../../tv/FocusEngine'
import { useAuth } from '../../context/AuthContext'
import { HomePage } from '../../pages/HomePage'
import { GridPage } from '../../pages/GridPage'
import { SearchPage } from '../../pages/SearchPage'
import { QueuePage } from '../../pages/QueuePage'
import { LibraryPage } from '../../pages/LibraryPage'
import { WatchlistPage } from '../../pages/WatchlistPage'
import { SettingsPage } from '../../pages/SettingsPage'
import './Shell.css'

export function Shell() {
  const [params, setParams] = useSearchParams()
  const { registerSidebar, setActiveSidebarRow } = useFocusEngine()
  const { switchProfile } = useAuth()
  const tabParam = params.get('tab')
  const tab: NavTab = isNavTab(tabParam) ? tabParam : DEFAULT_TAB
  const tabRef = useRef(tab)
  tabRef.current = tab

  const selectTab = useCallback(
    (next: NavTab) => {
      setParams(next === DEFAULT_TAB ? {} : { tab: next })
    },
    [setParams],
  )

  useEffect(() => {
    registerSidebar(SIDEBAR_ITEMS.length, (row) => {
      const item = SIDEBAR_ITEMS[row]
      if (!item) return
      // Focus is already correctly positioned by the caller (the keydown
      // handler's own `go()`, or a mouse click) before this fires — no need
      // to touch focus state here, just perform the actual navigation.
      if (item.tab === 'profile-switch') switchProfile()
      else selectTab(item.tab)
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Keep the "jump back to sidebar" target in sync with whichever tab is
  // actually active — regardless of how it got selected (click, keyboard,
  // or a direct URL/query-param load) — so Left/Up-at-top always lands on
  // the current tab instead of a stale row.
  useEffect(() => {
    const row = SIDEBAR_ITEMS.findIndex((item) => item.tab === tab)
    if (row >= 0) setActiveSidebarRow(row)
  }, [tab, setActiveSidebarRow])

  return (
    <div className="shell">
      <Sidebar active={tab} onSelect={selectTab} onProfileSwitch={switchProfile} />
      <MobileNav active={tab} onSelect={selectTab} onProfileSwitch={switchProfile} />
      <div className="main">
        <div className="content">
          {tab === 'home' && <HomePage />}
          {tab === 'grid-serien' && <GridPage kind="series" />}
          {tab === 'grid-anime' && <GridPage kind="anime" />}
          {tab === 'grid-filme' && <GridPage kind="movies" />}
          {tab === 'search' && <SearchPage />}
          {tab === 'queue' && <QueuePage />}
          {tab === 'library' && <LibraryPage />}
          {tab === 'watchlist' && <WatchlistPage />}
          {tab === 'settings' && <SettingsPage />}
        </div>
      </div>
    </div>
  )
}
