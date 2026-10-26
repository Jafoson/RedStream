import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { search, type SearchSite } from '../../api/search'
import { ErrorBox, PosterGrid, Spinner, TopBar } from '../components'
import { MIcon } from '../icons'

const SITES: { site: SearchSite; label: string }[] = [
  { site: 'aniworld', label: 'Anime' },
  { site: 'sto', label: 'Serien' },
  { site: 'megakino', label: 'Filme' },
]

export function SearchScreen() {
  const [text, setText] = useState('')
  const [query, setQuery] = useState('')
  const [site, setSite] = useState<SearchSite>('aniworld')
  const q = useQuery({ queryKey: ['m-search', site, query], queryFn: () => search(query, site), enabled: query !== '' })
  const submit = () => {
    setQuery(text.trim())
    ;(document.activeElement as HTMLElement | null)?.blur()
  }
  return (
    <>
      <TopBar title="Suche" />
      <div className="m-scroll">
        <form
          className="m-search"
          onSubmit={(e) => {
            e.preventDefault()
            submit()
          }}
        >
          <MIcon name="search" className="m-muted" />
          <input
            type="search"
            enterKeyHint="search"
            placeholder="Titel suchen…"
            value={text}
            autoCorrect="off"
            autoCapitalize="off"
            onChange={(e) => setText(e.target.value)}
          />
        </form>
        <div className="m-chips">
          {SITES.map((s) => (
            <button
              key={s.site}
              type="button"
              className={'m-chip' + (site === s.site ? ' active' : '')}
              onClick={() => {
                setSite(s.site)
                submit()
              }}
            >
              {s.label}
            </button>
          ))}
        </div>
        {q.isFetching && <Spinner />}
        {q.isError && <ErrorBox message={String((q.error as Error).message)} onRetry={() => q.refetch()} />}
        {q.data && q.data.length === 0 && <p className="m-muted m-pad">Keine Treffer für „{query}“.</p>}
        {q.data && <PosterGrid items={q.data} />}
      </div>
    </>
  )
}
