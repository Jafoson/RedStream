// Admin dashboard → Downloads: the download queue that used to be its own
// sidebar tab (QueuePage). Uses the regular /api/queue endpoints.
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  cancelQueueItem,
  clearCompleted,
  getQueue,
  moveQueueItem,
  removeQueueItem,
  type FfmpegProgress,
  type QueueItem,
  type QueueState,
} from '../../api/queue'
import { FfmpegBanner } from '../../components/queue/FfmpegBanner'
import { errorText, formatTime } from './format'

const STATUS_LABEL: Record<QueueItem['status'], string> = {
  queued: 'Wartend',
  running: 'Lädt herunter',
  completed: 'Fertig',
  failed: 'Fehlgeschlagen',
  cancelled: 'Abgebrochen',
}

const STATUS_CLASS: Record<QueueItem['status'], string> = {
  queued: 'pending',
  running: 'pending',
  completed: 'approved',
  failed: 'denied',
  cancelled: 'revoked',
}

const PRIORITY_LABEL: Record<number, string> = {
  0: 'Ansehen',
  1: 'Vorladen',
  2: 'Manuell',
  3: 'Auto-Sync',
}

function progressFor(item: QueueItem, all: QueueState['ffmpeg_progress'] | undefined): FfmpegProgress | null {
  if (!all) return null
  if ('percent' in all) return item.status === 'running' ? (all as FfmpegProgress) : null
  return (all as Record<string, FfmpegProgress>)[String(item.id)] ?? null
}

function parseErrors(item: QueueItem): { url: string | null; error: string }[] {
  try {
    const parsed = JSON.parse(item.errors || '[]')
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function DownloadsTab() {
  const queryClient = useQueryClient()
  const [message, setMessage] = useState<string | null>(null)
  const { data } = useQuery({ queryKey: ['queue'], queryFn: getQueue, refetchInterval: 2000 })

  const act = async (fn: () => Promise<unknown>) => {
    setMessage(null)
    try {
      await fn()
    } catch (err) {
      setMessage(errorText(err))
    }
    await queryClient.invalidateQueries({ queryKey: ['queue'] })
  }

  const items = data?.items ?? []
  const active = items.filter((i) => i.status === 'queued' || i.status === 'running')
  const finished = items.filter((i) => i.status !== 'queued' && i.status !== 'running')

  const renderItem = (item: QueueItem) => {
    const isActive = item.status === 'queued' || item.status === 'running'
    const progress = progressFor(item, data?.ffmpeg_progress)
    const errors = parseErrors(item)
    return (
      <div key={item.id} className="admin-row">
        <div className="admin-row__main">
          <div className="admin-row__title">
            <span className="admin-row__series">{item.title}</span>
            <span className={'admin-status admin-status--' + STATUS_CLASS[item.status]}>{STATUS_LABEL[item.status]}</span>
            <span className="admin-row__id">
              Folge {Math.min(item.current_episode + (item.status === 'running' ? 1 : 0), item.total_episodes)} / {item.total_episodes}
            </span>
          </div>
          <div className="admin-row__meta">
            {item.language} · {item.provider} · {PRIORITY_LABEL[item.priority] ?? `P${item.priority}`} · hinzugefügt {formatTime(item.created_at)}
            {item.completed_at && <> · beendet {formatTime(item.completed_at)}</>}
          </div>
          {item.status === 'running' &&
            (progress ? (
              <FfmpegBanner progress={progress} />
            ) : (
              <div className="admin-progress">
                <div className="admin-progress__bar" style={{ width: `${item.progress ?? 0}%` }} />
              </div>
            ))}
          {errors.length > 0 && (
            <details className="admin-errors">
              <summary>{errors.length} Fehler</summary>
              {errors.map((e, i) => (
                <div key={i} className="admin-errors__line">
                  {e.url && <span className="admin-errors__url">{e.url}</span>} {e.error}
                </div>
              ))}
            </details>
          )}
        </div>
        <div className="admin-row__actions">
          {isActive ? (
            <>
              <button type="button" className="filter btn-sm" title="Nach oben" onClick={() => act(() => moveQueueItem(item.id, 'up'))}>
                ↑
              </button>
              <button type="button" className="filter btn-sm" title="Nach unten" onClick={() => act(() => moveQueueItem(item.id, 'down'))}>
                ↓
              </button>
              <button type="button" className="filter btn-sm admin-danger" onClick={() => act(() => cancelQueueItem(item.id, true))}>
                Abbrechen
              </button>
            </>
          ) : (
            <button type="button" className="filter btn-sm" onClick={() => act(() => removeQueueItem(item.id))}>
              Entfernen
            </button>
          )}
        </div>
      </div>
    )
  }

  return (
    <>
      {message && <div className="admin-message">{message}</div>}
      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          Aktiv ({active.length})
        </div>
      </div>
      <div className="admin-list">
        {active.length ? active.map(renderItem) : <div className="admin-empty">Keine aktiven Downloads.</div>}
      </div>
      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          Abgeschlossen ({finished.length})
        </div>
        {finished.length > 0 && (
          <button type="button" className="filter btn-sm" onClick={() => act(clearCompleted)}>
            Fertige entfernen
          </button>
        )}
      </div>
      <div className="admin-list">
        {finished.length ? finished.map(renderItem) : <div className="admin-empty">Noch nichts abgeschlossen.</div>}
      </div>
    </>
  )
}
