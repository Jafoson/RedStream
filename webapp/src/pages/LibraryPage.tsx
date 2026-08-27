import { useMemo, useRef } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteFromLibrary, getLibrary, getStorageStats, type LibraryTitle } from '../api/library'
import { useExpandedSet } from '../hooks/useExpandedSet'
import { useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import './LibraryPage.css'

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 GB'
  const gb = bytes / 1024 ** 3
  return gb >= 1 ? `${gb.toFixed(1)} GB` : `${(bytes / 1024 ** 2).toFixed(0)} MB`
}

export function LibraryPage() {
  const queryClient = useQueryClient()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const library = useQuery({ queryKey: ['library'], queryFn: getLibrary })
  const storage = useQuery({ queryKey: ['storage-stats'], queryFn: getStorageStats })
  const { isExpanded, toggle } = useExpandedSet()

  function invalidate() {
    queryClient.invalidateQueries({ queryKey: ['library'] })
    queryClient.invalidateQueries({ queryKey: ['storage-stats'] })
  }

  const flatTitles = useMemo(
    () =>
      (library.data?.locations ?? []).flatMap((loc) =>
        loc.titles.map((title) => ({ location: loc, title, key: `${loc.label}:${title.folder}` })),
      ),
    [library.data],
  )

  useRegisterNav(
    [1, ...flatTitles.map(() => 1)],
    (row) => {
      if (row === 0) {
        invalidate()
        return
      }
      const entry = flatTitles[row - 1]
      if (entry) toggle(entry.key)
    },
    [flatTitles.map((t) => t.key).join(',')],
  )

  useAutoScrollRow(scrollerRef)

  function renderTitle(title: LibraryTitle, key: string, customPathId: number | null, row: number) {
    const open = isExpanded(key)
    const isFoc = focus.region === 'content' && focus.row === row
    return (
      <div
        key={key}
        className={'library-title panel row-anchor' + (isFoc ? ' is-foc' : '')}
        data-row={row}
        tabIndex={-1}
        onMouseEnter={(e) => setFocus({ region: 'content', row, col: 0 }, e)}
      >
        <button type="button" className="library-title__header" onClick={() => toggle(key)}>
          <span className="text-title-md">{title.folder}</span>
          <span className="text-body-md">
            {title.total_episodes} Episoden · {formatBytes(title.total_size)}
          </span>
        </button>
        {open && (
          <div className="library-title__body">
            {Object.entries(title.seasons).map(([season, files]) => (
              <div key={season} className="library-season">
                <span className="text-label-sm">Staffel {season}</span>
                {files.map((f) => (
                  <div key={f.file} className="library-episode">
                    <span className="text-body-md">
                      E{f.episode} · {formatBytes(f.size)}
                    </span>
                    <button
                      type="button"
                      className="filter"
                      onClick={() =>
                        deleteFromLibrary({
                          folder: title.folder,
                          season: Number(season),
                          episode: f.episode,
                          custom_path_id: customPathId,
                        }).then(invalidate)
                      }
                    >
                      Löschen
                    </button>
                  </div>
                ))}
              </div>
            ))}
            <button
              type="button"
              className="filter library-title__delete-all"
              onClick={() => deleteFromLibrary({ folder: title.folder, custom_path_id: customPathId }).then(invalidate)}
            >
              Ganze Serie löschen
            </button>
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="scroller" ref={scrollerRef}>
      <div className="grid-head" style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div>
          <div className="grid-eyebrow">REDSTREAM</div>
          <h1 className="grid-h1">Bibliothek</h1>
        </div>
        <button
          type="button"
          className={'filter' + (focus.region === 'content' && focus.row === 0 ? ' is-foc' : '')}
          onMouseEnter={(e) => setFocus({ region: 'content', row: 0, col: 0 }, e)}
          onClick={invalidate}
        >
          Aktualisieren
        </button>
      </div>

      {storage.data && (
        <div className="storage-banner panel">
          {storage.data.roots.map((root) => {
            const used = root.disk_total_bytes > 0 ? root.disk_used_bytes / root.disk_total_bytes : 0
            return (
              <div key={root.label} className="storage-banner__root">
                <div className="storage-banner__row">
                  <span className="text-body-md">{root.label}</span>
                  <span className="text-body-md">
                    RedStream: {formatBytes(root.downloads_bytes)} · frei {formatBytes(root.disk_free_bytes)}
                  </span>
                </div>
                <div className="storage-banner__bar">
                  <div className="storage-banner__fill" style={{ width: `${used * 100}%` }} />
                </div>
              </div>
            )
          })}
        </div>
      )}

      <div className="library-page__tree">
        {library.data?.locations.map((location) => (
          <div key={location.label} className="library-location">
            <h2 className="text-label-sm">{location.label}</h2>
            {location.titles.map((title) => {
              const key = `${location.label}:${title.folder}`
              const row = flatTitles.findIndex((t) => t.key === key) + 1
              return renderTitle(title, key, location.custom_path_id, row)
            })}
          </div>
        ))}
      </div>
      <div style={{ height: 40 }} />
    </div>
  )
}
