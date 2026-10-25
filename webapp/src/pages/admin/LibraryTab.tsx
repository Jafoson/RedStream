// Admin dashboard → Bibliothek: what's on disk and how much space it takes,
// with deletion per episode / season / title to free space. Replaces the old
// LibraryPage sidebar tab; uses the regular /api/library endpoints.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  deleteFromLibrary,
  getLibrary,
  getStorageStats,
  type DeleteFromLibraryInput,
  type LibraryLocation,
  type LibraryTitle,
} from '../../api/library'
import { useExpandedSet } from '../../hooks/useExpandedSet'
import { errorText, formatBytes } from './format'

type SortKey = 'size' | 'name' | 'episodes'

const SORTS: { value: SortKey; label: string }[] = [
  { value: 'size', label: 'Größte zuerst' },
  { value: 'name', label: 'Name A–Z' },
  { value: 'episodes', label: 'Meiste Folgen' },
]

interface Entry {
  key: string
  location: LibraryLocation
  title: LibraryTitle
}

// "Frieren (2023) [imdbid-tt22248376]" -> "Frieren (2023)"
function displayName(folder: string): string {
  return folder.replace(/\s*\[[^\]]*\]\s*$/, '').trim() || folder
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`
}

function seasonSize(files: LibraryTitle['seasons'][string]): number {
  return files.reduce((sum, f) => sum + (f.size || 0), 0)
}

export function LibraryTab() {
  const queryClient = useQueryClient()
  const library = useQuery({ queryKey: ['library'], queryFn: getLibrary })
  const storage = useQuery({ queryKey: ['storage-stats'], queryFn: getStorageStats })
  const { isExpanded, toggle } = useExpandedSet()
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<SortKey>('size')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null)

  const entries = useMemo<Entry[]>(() => {
    const all = (library.data?.locations ?? []).flatMap((location) =>
      location.titles.map((title) => ({ key: `${location.label}:${title.folder}`, location, title })),
    )
    const needle = search.trim().toLowerCase()
    const filtered = needle ? all.filter((e) => e.title.folder.toLowerCase().includes(needle)) : all
    return [...filtered].sort((a, b) => {
      if (sort === 'size') return b.title.total_size - a.title.total_size
      if (sort === 'episodes') return b.title.total_episodes - a.title.total_episodes
      return displayName(a.title.folder).localeCompare(displayName(b.title.folder), 'de')
    })
  }, [library.data, search, sort])

  const totals = useMemo(() => {
    const titles = (library.data?.locations ?? []).flatMap((l) => l.titles)
    return {
      titles: titles.length,
      episodes: titles.reduce((n, t) => n + t.total_episodes, 0),
      bytes: titles.reduce((n, t) => n + t.total_size, 0),
      largest: titles.reduce((m, t) => Math.max(m, t.total_size), 0),
    }
  }, [library.data])

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ['library'] }),
      queryClient.invalidateQueries({ queryKey: ['storage-stats'] }),
    ])

  const remove = async (input: DeleteFromLibraryInput, what: string, bytes: number) => {
    if (!window.confirm(`${what} löschen? Das gibt etwa ${formatBytes(bytes)} frei und lässt sich nicht rückgängig machen.`)) return
    setBusy(true)
    setMessage(null)
    try {
      await deleteFromLibrary(input)
      setMessage({ text: `${what} gelöscht – etwa ${formatBytes(bytes)} freigegeben.`, error: false })
      await refresh()
    } catch (err) {
      setMessage({ text: errorText(err), error: true })
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      {message && <div className={'admin-message' + (message.error ? '' : ' admin-message--ok')}>{message.text}</div>}

      <div className="admin-storage">
        {storage.data?.roots.map((root) => {
          const used = root.disk_total_bytes > 0 ? root.disk_used_bytes / root.disk_total_bytes : 0
          const ours = root.disk_total_bytes > 0 ? root.downloads_bytes / root.disk_total_bytes : 0
          return (
            <div key={root.label} className="admin-storage__card panel">
              <div className="admin-storage__head">
                <span className="admin-storage__label">{root.label}</span>
                <span className="admin-muted">{root.path}</span>
              </div>
              <div className="admin-storage__bar" title={`Belegt ${Math.round(used * 100)} %`}>
                <div className="admin-storage__used" style={{ width: `${used * 100}%` }} />
                <div className="admin-storage__ours" style={{ width: `${ours * 100}%` }} />
              </div>
              <div className="admin-storage__stats">
                <span><i className="admin-dot admin-dot--ours" /> RedStream {formatBytes(root.downloads_bytes)}</span>
                <span><i className="admin-dot admin-dot--used" /> Belegt {formatBytes(root.disk_used_bytes)} von {formatBytes(root.disk_total_bytes)}</span>
                <span className="admin-storage__free">Frei {formatBytes(root.disk_free_bytes)}</span>
              </div>
            </div>
          )
        })}
        <div className="admin-storage__card panel admin-storage__summary">
          <span className="admin-storage__big">{totals.titles}</span> Titel
          <span className="admin-storage__big">{totals.episodes}</span> Folgen
          <span className="admin-storage__big">{formatBytes(totals.bytes)}</span> gesamt
        </div>
      </div>

      <div className="admin-toolbar">
        <input
          className="text-input admin-search"
          type="search"
          placeholder="Titel suchen…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <label className="admin-sort">
          <span>Sortieren</span>
          <select value={sort} onChange={(e) => setSort(e.target.value as SortKey)}>
            {SORTS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </label>
        <button type="button" className="filter btn-sm" onClick={() => refresh()}>
          Aktualisieren
        </button>
      </div>

      <div className="admin-list">
        {entries.map(({ key, location, title }) => {
          const open = isExpanded(key)
          const share = totals.largest > 0 ? title.total_size / totals.largest : 0
          const base: DeleteFromLibraryInput = { folder: title.folder, custom_path_id: location.custom_path_id }
          const name = displayName(title.folder)
          return (
            <div key={key} className="admin-row admin-row--stack">
              <button type="button" className="admin-lib__head" onClick={() => toggle(key)} aria-expanded={open}>
                <span className="admin-lib__chevron">{open ? '▾' : '▸'}</span>
                <span className="admin-lib__name">{name}</span>
                <span className="admin-lib__meta">
                  {plural(title.total_episodes, 'Folge', 'Folgen')} · {plural(Object.keys(title.seasons).length, 'Staffel', 'Staffeln')}
                  {(library.data?.locations.length ?? 0) > 1 && <> · {location.label}</>}
                </span>
                <span className="admin-lib__size">{formatBytes(title.total_size)}</span>
              </button>
              <div className="admin-progress admin-lib__share">
                <div className="admin-progress__bar" style={{ width: `${share * 100}%` }} />
              </div>
              {open && (
                <div className="admin-lib__body">
                  {Object.entries(title.seasons)
                    .sort(([a], [b]) => Number(a) - Number(b))
                    .map(([season, files]) => (
                      <div key={season} className="admin-lib__season">
                        <div className="admin-lib__season-head">
                          <span className="admin-lib__season-title">Staffel {season}</span>
                          <span className="admin-muted">
                            {plural(files.length, 'Folge', 'Folgen')} · {formatBytes(seasonSize(files))}
                          </span>
                          <button
                            type="button"
                            className="filter btn-sm admin-danger"
                            disabled={busy}
                            onClick={() => remove({ ...base, season: Number(season) }, `„${name}“ Staffel ${season}`, seasonSize(files))}
                          >
                            Staffel löschen
                          </button>
                        </div>
                        <div className="admin-lib__episodes">
                          {[...files]
                            .sort((a, b) => a.episode - b.episode)
                            .map((f) => (
                              <div key={f.file} className="admin-lib__episode">
                                <span>Folge {f.episode}</span>
                                <span className="admin-muted">{formatBytes(f.size)}</span>
                                <button
                                  type="button"
                                  className="filter btn-sm admin-danger"
                                  disabled={busy}
                                  onClick={() =>
                                    remove(
                                      { ...base, season: Number(season), episode: f.episode },
                                      `„${name}“ S${String(season).padStart(2, '0')}E${String(f.episode).padStart(2, '0')}`,
                                      f.size,
                                    )
                                  }
                                >
                                  Löschen
                                </button>
                              </div>
                            ))}
                        </div>
                      </div>
                    ))}
                  <button
                    type="button"
                    className="filter btn-sm admin-danger admin-lib__delete-all"
                    disabled={busy}
                    onClick={() => remove(base, `„${name}“ komplett`, title.total_size)}
                  >
                    Ganzen Titel löschen ({formatBytes(title.total_size)})
                  </button>
                </div>
              )}
            </div>
          )
        })}
        {!library.isLoading && entries.length === 0 && (
          <div className="admin-empty">{search ? 'Nichts gefunden.' : 'Noch keine Downloads vorhanden.'}</div>
        )}
      </div>
    </>
  )
}
