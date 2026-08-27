import { useSyncExternalStore } from 'react'
import { computeIsTv, subscribeTv } from './detectTv'

// Only Settings' toggle display and useGridColumns (for the TV column cap)
// need this as a React value — GridPage's own visual treatment reads
// [data-tv] directly in CSS and doesn't need a re-render when it flips.
export function useIsTv(): boolean {
  return useSyncExternalStore(subscribeTv, computeIsTv)
}
