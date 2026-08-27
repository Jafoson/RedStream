import { useRef } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  cancelQueueItem,
  clearCompleted,
  getQueue,
  moveQueueItem,
  removeQueueItem,
  type FfmpegProgress,
  type QueueItem,
} from '../api/queue'
import { FfmpegBanner } from '../components/queue/FfmpegBanner'
import { useFocusEngine, useRegisterNav } from '../tv/FocusEngine'
import { useAutoScrollRow } from '../tv/alignRow'
import './QueuePage.css'

const STATUS_LABEL: Record<QueueItem['status'], string> = {
  queued: 'Wartend',
  running: 'Lädt herunter',
  completed: 'Fertig',
  failed: 'Fehlgeschlagen',
  cancelled: 'Abgebrochen',
}

function progressFor(item: QueueItem, all: QueueState['ffmpeg_progress']): FfmpegProgress | null {
  if (!all) return null
  if ('percent' in all) return all as FfmpegProgress
  const map = all as Record<string, FfmpegProgress>
  return map[String(item.id)] ?? null
}

type QueueState = Awaited<ReturnType<typeof getQueue>>

export function QueuePage() {
  const queryClient = useQueryClient()
  const { focus, setFocus } = useFocusEngine()
  const scrollerRef = useRef<HTMLDivElement>(null)
  const { data } = useQuery({
    queryKey: ['queue'],
    queryFn: getQueue,
    refetchInterval: 2000,
  })

  function invalidate() {
    queryClient.invalidateQueries({ queryKey: ['queue'] })
  }

  const items = data?.items ?? []
  const active = items.filter((i) => i.status === 'queued' || i.status === 'running')
  const completed = items.filter((i) => i.status === 'completed' || i.status === 'failed' || i.status === 'cancelled')
  const all = [...active, ...completed]

  useRegisterNav(
    all.map(() => 1),
    (row) => {
      const item = all[row]
      if (!item) return
      const isActive = row < active.length
      if (isActive) cancelQueueItem(item.id, true).then(invalidate)
      else removeQueueItem(item.id).then(invalidate)
    },
    [all.map((i) => i.id).join(',')],
  )

  useAutoScrollRow(scrollerRef)

  return (
    <div className="scroller" ref={scrollerRef}>
      <div className="grid-head" style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div>
          <div className="grid-eyebrow">REDSTREAM</div>
          <h1 className="grid-h1">Downloads</h1>
        </div>
        {completed.length > 0 && (
          <button type="button" className="filter" onClick={() => clearCompleted().then(invalidate)}>
            Fertige entfernen
          </button>
        )}
      </div>

      <div className="section-head">
        <div className="section-title">
          <span className="bar" />
          Aktiv
        </div>
      </div>
      {active.length === 0 && (
        <p className="text-body-md" style={{ padding: '0 44px' }}>
          Keine aktiven Downloads.
        </p>
      )}
      <div className="queue-page__list">
        {active.map((item, i) => {
          const progress = data ? progressFor(item, data.ffmpeg_progress) : null
          const isFoc = focus.region === 'content' && focus.row === i
          return (
            <div
              key={item.id}
              className={'queue-item panel row-anchor' + (isFoc ? ' is-foc' : '')}
              data-row={i}
              onMouseEnter={(e) => setFocus({ region: 'content', row: i, col: 0 }, e)}
            >
              <div className="queue-item__row">
                <div className="queue-item__info">
                  <span className="text-title-md">{item.title}</span>
                  <span className="text-body-md">{STATUS_LABEL[item.status]}</span>
                </div>
                <div className="queue-item__actions">
                  <button type="button" className="filter" onClick={() => moveQueueItem(item.id, 'up').then(invalidate)}>
                    ↑
                  </button>
                  <button type="button" className="filter" onClick={() => moveQueueItem(item.id, 'down').then(invalidate)}>
                    ↓
                  </button>
                  <button type="button" className="filter" onClick={() => cancelQueueItem(item.id, true).then(invalidate)}>
                    Abbrechen
                  </button>
                </div>
              </div>
              {progress ? (
                <FfmpegBanner progress={progress} />
              ) : (
                <div className="queue-item__bar">
                  <div className="queue-item__bar-fill" style={{ width: `${item.progress ?? 0}%` }} />
                </div>
              )}
            </div>
          )
        })}
      </div>

      <div className="section-head" style={{ marginTop: 30 }}>
        <div className="section-title">
          <span className="bar" />
          Abgeschlossen
        </div>
      </div>
      <div className="queue-page__list">
        {completed.map((item, i) => {
          const row = active.length + i
          const isFoc = focus.region === 'content' && focus.row === row
          return (
            <div
              key={item.id}
              className={'queue-item panel row-anchor' + (isFoc ? ' is-foc' : '')}
              data-row={row}
              onMouseEnter={(e) => setFocus({ region: 'content', row, col: 0 }, e)}
            >
              <div className="queue-item__row">
                <div className="queue-item__info">
                  <span className="text-title-md">{item.title}</span>
                  <span className="text-body-md">{STATUS_LABEL[item.status]}</span>
                </div>
                <button type="button" className="filter" onClick={() => removeQueueItem(item.id).then(invalidate)}>
                  Entfernen
                </button>
              </div>
            </div>
          )
        })}
      </div>
      <div style={{ height: 40 }} />
    </div>
  )
}
