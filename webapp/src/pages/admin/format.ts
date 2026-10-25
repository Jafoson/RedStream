// Small formatting helpers shared by the admin dashboard's tabs.

// SQLite's datetime('now') is UTC without a zone marker.
export function parseUtc(value: string | null | undefined): Date | null {
  if (!value) return null
  const d = new Date(value.replace(' ', 'T') + 'Z')
  return Number.isNaN(d.getTime()) ? null : d
}

export function formatTime(value: string | null | undefined): string {
  const d = parseUtc(value)
  return d
    ? d.toLocaleString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : '—'
}

export function formatBytes(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 MB'
  const gb = bytes / 1024 ** 3
  if (gb >= 1) return `${gb.toFixed(gb >= 100 ? 0 : 1)} GB`
  return `${Math.max(1, Math.round(bytes / 1024 ** 2))} MB`
}

export function errorText(err: unknown): string {
  return err instanceof Error ? err.message : 'Unbekannter Fehler'
}
