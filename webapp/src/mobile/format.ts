/** Site language keys -> what you hear/read (same wording as the web player and the native apps). */
export function languageLabel(lang: string): string {
  switch (lang) {
    case 'German Dub':
      return 'Deutsch'
    case 'English Dub':
      return 'Englisch'
    case 'German Sub':
      return 'Japanisch · deutsche Untertitel'
    case 'English Sub':
      return 'Japanisch · englische Untertitel'
    default:
      return lang
  }
}

/** Compact form for episode rows, where both sub variants would otherwise read "Japanisch". */
export function shortLanguageLabel(lang: string): string {
  if (lang === 'German Sub') return 'Untertitel DE'
  if (lang === 'English Sub') return 'Untertitel EN'
  return languageLabel(lang)
}

const ORDER = ['German Dub', 'German Sub', 'English Sub', 'English Dub']

export function sortLanguages(langs: Iterable<string>): string[] {
  const rank = (l: string) => (ORDER.indexOf(l) < 0 ? 99 : ORDER.indexOf(l))
  return [...new Set(langs)].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
}

export function epCode(season: number, episode: number): string {
  return `S${String(season).padStart(2, '0')}E${String(episode).padStart(2, '0')}`
}

export function formatTime(seconds?: number | null): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? (seconds as number) : 0))
  const mm = String(Math.floor(s / 60) % 60).padStart(2, '0')
  const ss = String(s % 60).padStart(2, '0')
  return s >= 3600 ? `${Math.floor(s / 3600)}:${mm}:${ss}` : `${Math.floor(s / 60)}:${ss}`
}
