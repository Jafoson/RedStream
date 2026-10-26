import { useEffect, useRef, useState } from 'react'
import { useInfiniteQuery } from '@tanstack/react-query'
import { getAllByKind, type GridKind } from '../../api/browse'
import { ErrorBox, PosterGrid, Spinner, TopBar } from '../components'

const KINDS: { kind: GridKind; label: string }[] = [
  { kind: 'series', label: 'Serien' },
  { kind: 'anime', label: 'Anime' },
  { kind: 'movies', label: 'Filme' },
]

export function BrowseScreen() {
  const [kind, setKind] = useState<GridKind>('series')
  const [genre, setGenre] = useState<string | null>(null)
  const sentinel = useRef<HTMLDivElement>(null)
  const q = useInfiniteQuery({
    queryKey: ['m-browse', kind, genre],
    queryFn: ({ pageParam }) => getAllByKind(kind, pageParam, genre ?? undefined),
    initialPageParam: 1,
    getNextPageParam: (last) => (last.has_more ? last.page + 1 : undefined),
  })
  const items = q.data?.pages.flatMap((p) => p.results) ?? []
  const unique = items.filter((it, i) => items.findIndex((o) => o.url === it.url) === i)
  const genres = q.data?.pages[0]?.all_genres ?? []

  // Next page when the end of the grid scrolls into view.
  useEffect(() => {
    const el = sentinel.current
    if (!el) return
    const io = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting && q.hasNextPage && !q.isFetchingNextPage) q.fetchNextPage()
    })
    io.observe(el)
    return () => io.disconnect()
  }, [q])

  return (
    <>
      <TopBar title="Entdecken" />
      <div className="m-scroll">
        <div className="m-segmented">
          {KINDS.map((k) => (
            <button
              key={k.kind}
              type="button"
              className={k.kind === kind ? 'active' : ''}
              onClick={() => {
                setKind(k.kind)
                setGenre(null)
              }}
            >
              {k.label}
            </button>
          ))}
        </div>
        {genres.length > 0 && (
          <div className="m-chips">
            <button type="button" className={'m-chip' + (genre === null ? ' active' : '')} onClick={() => setGenre(null)}>
              Alle
            </button>
            {genres.map((g) => (
              <button key={g} type="button" className={'m-chip' + (genre === g ? ' active' : '')} onClick={() => setGenre(g)}>
                {g}
              </button>
            ))}
          </div>
        )}
        <PosterGrid items={unique} />
        {q.isError && <ErrorBox message={String((q.error as Error).message)} onRetry={() => q.refetch()} />}
        {(q.isLoading || q.isFetchingNextPage) && <Spinner />}
        {!q.isLoading && !q.isError && unique.length === 0 && <p className="m-muted m-pad">Nichts gefunden.</p>}
        <div ref={sentinel} style={{ height: 1 }} />
      </div>
    </>
  )
}
