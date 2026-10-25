// Mirrors app/lib/navigation/app_nav.dart's NavScreen enum — the set of
// screens the Flutter app swaps in-place inside its shell (never a real
// navigation push). We keep the same tab set, synced to a `?tab=` query
// param instead of an in-memory-only controller, so browser back/reload
// preserve the active tab (a deliberate small web-native improvement).
export type NavTab =
  | 'home'
  | 'grid-serien'
  | 'grid-anime'
  | 'grid-filme'
  | 'search'
  | 'watchlist'
  | 'settings'

export const DEFAULT_TAB: NavTab = 'home'

export function isNavTab(value: string | null): value is NavTab {
  return (
    value === 'home' ||
    value === 'grid-serien' ||
    value === 'grid-anime' ||
    value === 'grid-filme' ||
    value === 'search' ||
    value === 'watchlist' ||
    value === 'settings'
  )
}

// Flat sidebar row order — index in this array IS the FocusEngine sidebar
// row number. Ported from the Claude Design project's components.jsx
// NAV_ALL grouping (MENÜ / Einstellungen / Profil wechseln). Downloads and
// Bibliothek used to be a BIBLIOTHEK group here; they now live in the admin
// dashboard (/verwaltung, pages/AdminPage.tsx) instead.
export interface SidebarItem {
  tab: NavTab | 'profile-switch'
  label: string
  icon: string
  group: 'menu' | 'general' | 'profile'
}

export const SIDEBAR_ITEMS: SidebarItem[] = [
  { tab: 'home', label: 'Home', icon: 'home', group: 'menu' },
  { tab: 'watchlist', label: 'Meine Liste', icon: 'heart', group: 'menu' },
  { tab: 'grid-serien', label: 'Serien', icon: 'series', group: 'menu' },
  { tab: 'grid-filme', label: 'Filme', icon: 'film', group: 'menu' },
  { tab: 'grid-anime', label: 'Anime', icon: 'anime', group: 'menu' },
  { tab: 'search', label: 'Suche', icon: 'search', group: 'menu' },
  { tab: 'settings', label: 'Einstellungen', icon: 'settings', group: 'general' },
  { tab: 'profile-switch', label: 'Profil wechseln', icon: 'swap', group: 'profile' },
]
