import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getNewAnimes, getNewSeries, getPopularAnimes, getPopularMovies, getPopularSeries, type BrowseItem } from '../../api/browse'
import { getAllProgress, type ProgressEntry } from '../../api/stream'
import { Poster, PosterCard, ProgressLine, SectionTitle, TopBar, openSeries, usePlay } from '../components'
import { epCode } from '../format'
import { InstallBanner } from '../InstallHint'

const RAILS: [string, string, () => Promise<BrowseItem[]>][] = [
  ['Neue Anime', 'new-animes', getNewAnimes],
  ['Beliebte Anime', 'popular-animes', getPopularAnimes],
  ['Neue Serien', 'new-series', getNewSeries],
  ['Beliebte Serien', 'popular-series', getPopularSeries],
  ['Beliebte Filme', 'popular-movies', getPopularMovies],
]

export function HomeScreen() {
  const play = usePlay()
  const cont = useQuery({
    queryKey: ['m-continue'],
    queryFn: () => getAllProgress({ continueOnly: true, limit: 20 }),
    refetchOnMount: 'always',
  })
  return (
    <>
      <TopBar title="Start" />
      <div className="m-scroll">
        <InstallBanner />
        {(cont.data?.length ?? 0) > 0 && (
          <>
            <SectionTitle>Weiterschauen</SectionTitle>
            <div className="m-rail">
              {cont.data!.map((p) => (
                <ContinueCard
                  key={p.episode_url}
                  entry={p}
                  onClick={() =>
                    play({
                      episodeUrl: p.episode_url,
                      seriesTitle: p.series_title || '',
                      seriesUrl: p.series_url || '',
                      season: p.season,
                      episodeNumber: p.episode_number,
                      episodeTitle: p.episode_title || undefined,
                    })
                  }
                />
              ))}
            </div>
          </>
        )}
        {RAILS.map(([title, key, fn]) => (
          <Rail key={key} title={title} queryKey={key} fetcher={fn} />
        ))}
      </div>
    </>
  )
}

function Rail({ title, queryKey, fetcher }: { title: string; queryKey: string; fetcher: () => Promise<BrowseItem[]> }) {
  const navigate = useNavigate()
  const q = useQuery({ queryKey: ['m-rail', queryKey], queryFn: fetcher, staleTime: 5 * 60_000 })
  if (!q.data?.length) return null
  return (
    <>
      <SectionTitle>{title}</SectionTitle>
      <div className="m-rail">
        {q.data.map((it) => (
          <div key={it.url} className="m-rail__poster">
            <PosterCard title={it.title} image={it.poster_url} onClick={() => openSeries(navigate, it.url, it.title)} />
          </div>
        ))}
      </div>
    </>
  )
}

function ContinueCard({ entry, onClick }: { entry: ProgressEntry; onClick: () => void }) {
  const image = entry.preview_url || entry.backdrop_url || entry.poster_url
  const fraction = entry.completed ? 1 : entry.duration_seconds > 0 ? entry.position_seconds / entry.duration_seconds : 0
  return (
    <button type="button" className="m-continue" onClick={onClick}>
      <div className="m-continue__image">
        <Poster title={entry.series_title || ''} image={image} className="m-poster--wide" />
        <ProgressLine fraction={fraction} className="m-continue__progress" />
      </div>
      <span className="m-card__title">{entry.series_title}</span>
      <span className="m-card__sub">
        {epCode(entry.season, entry.episode_number)}
        {entry.episode_title ? ` · ${entry.episode_title}` : ''}
      </span>
    </button>
  )
}
