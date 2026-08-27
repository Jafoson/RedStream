// Single source of truth for the tablet/mobile tier boundaries — CSS files
// can't import these directly (no PostCSS custom-media tooling in this repo),
// so every `@media` block using these numbers carries a comment pointing back
// here. Keep them in sync by hand; this is the same level of convention this
// codebase already relies on elsewhere (e.g. GridPage's COLS constant used to
// have to match its own CSS by hand before useGridColumns unified them).
export const MOBILE_S_MAX = 479
export const MOBILE_L_MAX = 639
export const TABLET_MAX = 1023
export const LAPTOP_MAX = 1439

// Below this width the sidebar becomes a bottom nav bar (touch-primary
// devices — phones, portrait tablets); at/above it, mouse/trackpad/D-pad is
// the primary input and there's room for the collapsed 96px icon rail.
export const SIDEBAR_BREAKPOINT = TABLET_MAX
