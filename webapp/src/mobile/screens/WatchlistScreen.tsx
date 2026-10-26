import { useQuery } from '@tanstack/react-query'
import { getWatchlist } from '../../api/watchlist'
import { ErrorBox, PosterGrid, Spinner, TopBar } from '../components'

export function WatchlistScreen() {
  const q = useQuery({ queryKey: ['m-watchlist'], queryFn: getWatchlist, refetchOnMount: 'always' })
  return (
    <>
      <TopBar title="Meine Liste" />
      <div className="m-scroll">
        {q.isLoading && <Spinner />}
        {q.isError && <ErrorBox message={String((q.error as Error).message)} onRetry={() => q.refetch()} />}
        {q.data && q.data.length === 0 && (
          <p className="m-muted m-pad">Noch nichts auf deiner Liste. Auf der Seite einer Serie kannst du sie hinzufügen.</p>
        )}
        {q.data && <PosterGrid items={q.data} />}
      </div>
    </>
  )
}
