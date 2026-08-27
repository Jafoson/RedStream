// Line-icon set ported verbatim from the Claude Design project's
// components.jsx (PATHS) — same 24x24 viewBox line-art kit.
import type { SVGProps } from 'react'

const PATHS: Record<string, string> = {
  home: 'M3 10.5 12 3l9 7.5M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5',
  series: 'M3 7h18v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V7Zm0 0 3-4h12l3 4M9 3v4M15 3v4',
  anime:
    'M12 3c4.5 0 8 3 8 7 0 2.5-1.6 4.2-3.5 4.8L17 21l-5-3-5 3 .5-6.2C5.6 14.2 4 12.5 4 10c0-4 3.5-7 8-7Z',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM21 21l-4.3-4.3',
  list: 'M5 5h11M5 12h11M5 19h7M19 16v6M16 19h6',
  heart:
    'M12 20s-7-4.3-9.3-8.5C1 8 2.7 4.5 6 4.5c2 0 3.2 1.2 4 2.3.8-1.1 2-2.3 4-2.3 3.3 0 5 3.5 3.3 7C19 15.7 12 20 12 20Z',
  calendar: 'M7 3v3M17 3v3M4 8h16M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Z',
  settings:
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm8-3a8 8 0 0 0-.2-1.7l2-1.5-2-3.4-2.3 1a8 8 0 0 0-3-1.7L14 2h-4l-.5 2.6a8 8 0 0 0-3 1.7l-2.3-1-2 3.4 2 1.5A8 8 0 0 0 4 12c0 .6 0 1.1.2 1.7l-2 1.5 2 3.4 2.3-1a8 8 0 0 0 3 1.7L10 22h4l.5-2.6a8 8 0 0 0 3-1.7l2.3 1 2-3.4-2-1.5c.1-.6.2-1.1.2-1.7Z',
  logout:
    'M15 5V4a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1v-1M9 12h12m0 0-3.5-3.5M21 12l-3.5 3.5',
  play: 'M6 4.5v15l13-7.5-13-7.5Z',
  plus: 'M12 5v14M5 12h14',
  check: 'M4 12.5 9 17.5 20 6.5',
  star: 'M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 17l-5.2 2.6 1-5.8L3.5 9.7l5.9-.9L12 3.5Z',
  bell: 'M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6ZM10 20a2 2 0 0 0 4 0',
  chevL: 'M15 5l-7 7 7 7',
  chevR: 'M9 5l7 7-7 7',
  back: 'M11 5l-7 7 7 7M4 12h16',
  info: 'M12 16v-5M12 8h.01M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z',
  trailer:
    'M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Zm6 3.5v7l5-3.5-5-3.5Z',
  flame:
    'M12 3c1 3-1 4-1 6 0 1 .8 2 2 2s2-1 2-2.5C18 11 19 13 19 15a7 7 0 1 1-14 0c0-3 2-5 3-7 1.5 2 3 2 4 1 1-1 0-4 0-6Z',
  space: 'M5 9v4a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9',
  del: 'M9 6h11a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-6-6 6-6Zm2.5 3.5 5 5m0-5-5 5',
  pause: 'M8 5h3v14H8zM13 5h3v14h-3z',
  cc: 'M4 6a1.5 1.5 0 0 1 1.5-1.5h13A1.5 1.5 0 0 1 20 6v12a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18V6Zm4 4.7h3M8 14h3m2-3.3h3M13 14h3',
  skipnext: 'M6 5l8.5 7L6 19V5ZM17 5v14',
  close: 'M6 6l12 12M18 6 6 18',
  film: 'M4 4h16a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Zm4 0v16m8-16v16M3 9h5m8 0h5M3 15h5m8 0h5',
  download: 'M12 3v11m0 0-4-4m4 4 4-4M4 17v2a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-2',
  swap: 'M7 8h13m0 0-3-3m3 3-3 3M17 16H4m0 0 3-3m-3 3 3 3',
  library: 'M4 5h4v15H4V5Zm6 0h4v15h-4V5Zm7.2.6 3.6 1-3.4 13.5-3.6-1L17.2 5.6Z',
  volumeHigh: 'M11 5 6 9 2 9 2 15 6 15 11 19 11 5Z M15.5 8.5a5 5 0 0 1 0 7 M19 5a10 10 0 0 1 0 14',
  volumeLow: 'M11 5 6 9 2 9 2 15 6 15 11 19 11 5Z M15.5 8.5a5 5 0 0 1 0 7',
  volumeMute: 'M11 5 6 9 2 9 2 15 6 15 11 19 11 5Z M17 9l6 6 M23 9l-6 6',
}

export function Icon({ name, w = 22 }: { name: string; w?: number }) {
  const filled = name === 'play' || name === 'star' || name === 'pause'
  return (
    <svg
      viewBox="0 0 24 24"
      width={w}
      height={w}
      fill={filled ? 'currentColor' : 'none'}
      stroke={filled ? 'none' : 'currentColor'}
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d={PATHS[name] || ''} />
    </svg>
  )
}

export const BackIcon = (p: SVGProps<SVGSVGElement>) => <Icon name="back" w={Number(p.width) || 18} />
