import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { getEpisodes, getPreferredLanguage, getSeasons, getSeriesDetail, setSeriesLanguage, type Episode } from '../../api/series'
import { getAllProgress, type ProgressEntry } from '../../api/stream'
import { addToWatchlist, isInWatchlist, removeFromWatchlist } from '../../api/watchlist'
import { useCast } from '../CastContext'
import { ErrorBox, Poster, ProgressLine, Spinner, TopBar, useMToast, usePlay } from '../components'
import { epCode, languageLabel, shortLanguageLabel, sortLanguages } from '../format'
import { MIcon } from '../icons'
import type { PlayItem } from '../types'

export function DetailScreen() {
  const [params] = useSearchParams()
  const seriesUrl = params.get('url') || ''
  const initialTitle = params.get('title') || ''
  const play = usePlay()
  const cast = useCast()
  const toast = useMToast()
  const queryClient = useQueryClient()

  const detail = useQuery({ queryKey: ['m-series', seriesUrl], queryFn: () => getSeriesDetail(seriesUrl), enabled: !!seriesUrl })
  const seasons = useQuery({ queryKey: ['m-seasons', seriesUrl], queryFn: () => getSeasons(seriesUrl), enabled: !!seriesUrl })
  const inList = useQuery({ queryKey: ['m-inlist', seriesUrl], queryFn: () => isInWatchlist(seriesUrl), enabled: !!seriesUrl })
  const prefLang = useQuery({ queryKey: ['m-lang', seriesUrl], queryFn: () => getPreferredLanguage(seriesUrl), enabled: !!seriesUrl })
  // Polled like the web app's detail page, so progress stays current after
  // coming back from the player or while a TV plays this series.
  const progressQ = useQuery({
    queryKey: ['m-progress-all'],
    queryFn: () => getAllProgress({ limit: 500 }),
    refetchInterval: 8000,
    refetchOnMount: 'always',
  })
  const progress = useMemo(() => {
    const map = new Map<string, ProgressEntry>()
    for (const p of progressQ.data ?? []) if (p.series_url === seriesUrl) map.set(p.episode_url, p)
    return map
  }, [progressQ.data, seriesUrl])

  const [seasonIndex, setSeasonIndex] = useState<number | null>(null)
  const [language, setLanguage] = useState<string | null>(null)
  const [expanded, setExpanded] = useState(false)
  const [menuFor, setMenuFor] = useState<string | null>(null)
  const [langMenu, setLangMenu] = useState(false)

  useEffect(() => {
    if (prefLang.data && language === null) setLanguage(prefLang.data)
  }, [prefLang.data, language])

  // Start on the season of the furthest-watched episode.
  useEffect(() => {
    if (seasonIndex !== null || !seasons.data?.length || !progressQ.isFetched) return
    let frontier: ProgressEntry | null = null
    for (const p of progress.values()) {
      if (!frontier || p.season * 10000 + p.episode_number > frontier.season * 10000 + frontier.episode_number) frontier = p
    }
    const idx = seasons.data.findIndex((s) => s.season_number === frontier?.season)
    setSeasonIndex(idx >= 0 ? idx : 0)
  }, [seasons.data, progress, progressQ.isFetched, seasonIndex])

  const season = seasons.data?.[Math.max(0, Math.min(seasonIndex ?? 0, (seasons.data?.length ?? 1) - 1))]
  const episodes = useQuery({ queryKey: ['m-episodes', season?.url], queryFn: () => getEpisodes(season!.url), enabled: !!season })
  const epList = episodes.data ?? []
  const title = detail.data?.title || initialTitle

  const item = (ep: Episode): PlayItem => ({
    episodeUrl: ep.url,
    seriesTitle: title,
    seriesUrl,
    season: season?.season_number ?? 1,
    episodeNumber: ep.episode_number,
    episodeTitle: (ep.title_de || ep.title_en || '').trim() || undefined,
    absoluteEpisodeNumber: ep.absolute_episode_number,
    language: language ?? undefined,
    folder: ep.downloaded ? ep.folder : null,
  })

  // "Weiterschauen": the furthest episode of this season that was started
  // and not finished, else the one after the furthest finished one.
  const nextUp = useMemo(() => {
    if (!epList.length) return null
    const watched = epList.filter((e) => progress.has(e.url))
    if (!watched.length) return epList[0]
    const furthest = watched.reduce((a, b) => (b.episode_number > a.episode_number ? b : a))
    if (!progress.get(furthest.url)?.completed) return furthest
    return epList.find((e) => e.episode_number > furthest.episode_number) ?? furthest
  }, [epList, progress])

  const available = sortLanguages(epList.flatMap((e) => e.available_languages ?? []))
  const languageOptions = language && !available.includes(language) ? [...available, language] : available

  const toggleList = async () => {
    try {
      if (inList.data) await removeFromWatchlist(seriesUrl)
      else await addToWatchlist(seriesUrl, title, detail.data?.poster_url)
      queryClient.setQueryData(['m-inlist', seriesUrl], !inList.data)
      queryClient.invalidateQueries({ queryKey: ['m-watchlist'] })
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    }
  }

  const pickLanguage = (lang: string) => {
    setLangMenu(false)
    setLanguage(lang)
    setSeriesLanguage(seriesUrl, lang).catch(() => {})
  }

  const backdrop = detail.data?.backdrop_url || detail.data?.poster_url
  const meta = [detail.data?.release_year, (detail.data?.genres ?? []).slice(0, 3).join(' · ')].filter(Boolean).join('  ·  ')
  const started = nextUp ? progress.has(nextUp.url) : false

  return (
    <>
      <TopBar title="" large={false} back />
      <div className="m-scroll">
        <div className="m-hero">
          <Poster title="" image={backdrop} className="m-poster--wide" />
          <div className="m-hero__shade" />
          <div className="m-hero__text">
            <h1>{title}</h1>
            {meta && <p className="m-muted">{meta}</p>}
          </div>
        </div>

        <div className="m-actions">
          <button type="button" className="m-btn m-btn--primary m-btn--grow" disabled={!nextUp} onClick={() => nextUp && play(item(nextUp))}>
            <MIcon name={cast.target ? 'tv' : 'play'} size={20} />
            {nextUp ? `${started ? 'Weiterschauen' : 'Abspielen'} ${epCode(season?.season_number ?? 1, nextUp.episode_number)}` : 'Abspielen'}
          </button>
          <button type="button" className={'m-icon-btn' + (inList.data ? ' m-accent' : '')} aria-label="Meine Liste" onClick={toggleList}>
            <MIcon name={inList.data ? 'bookmark' : 'bookmarkOutline'} size={28} />
          </button>
        </div>

        {languageOptions.length > 0 && (
          <div className="m-langpick">
            <button type="button" className="m-btn m-btn--outline" onClick={() => setLangMenu((v) => !v)}>
              <MIcon name="translate" size={18} />
              {language ? languageLabel(language) : 'Sprache'}
            </button>
            {langMenu && (
              <div className="m-menu">
                {languageOptions.map((l) => (
                  <button key={l} type="button" onClick={() => pickLanguage(l)}>
                    <span className="m-menu__check">{l === language && <MIcon name="check" size={18} />}</span>
                    {languageLabel(l)}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {detail.data?.description && (
          <p className={'m-desc' + (expanded ? ' expanded' : '')} onClick={() => setExpanded((v) => !v)}>
            {detail.data.description}
          </p>
        )}

        {seasons.isLoading && <Spinner />}
        {seasons.isError && <ErrorBox message={String((seasons.error as Error).message)} onRetry={() => seasons.refetch()} />}
        {(seasons.data?.length ?? 0) > 1 && (
          <div className="m-tabs">
            {seasons.data!.map((s, i) => (
              <button key={s.url} type="button" className={i === (seasonIndex ?? 0) ? 'active' : ''} onClick={() => setSeasonIndex(i)}>
                {s.are_movies ? 'Filme' : `Staffel ${s.season_number}`}
              </button>
            ))}
          </div>
        )}

        {episodes.isLoading && season && <Spinner />}
        {episodes.isError && <ErrorBox message={String((episodes.error as Error).message)} onRetry={() => episodes.refetch()} />}
        <div className="m-episodes">
          {epList.map((ep) => {
            const p = progress.get(ep.url)
            const epTitle = (ep.title_de || ep.title_en || '').trim() || `Folge ${ep.episode_number}`
            return (
              <div key={ep.url} className="m-episode">
                <button type="button" className="m-episode__main" onClick={() => play(item(ep))}>
                  <span className="m-episode__num">{ep.episode_number}</span>
                  <span className="m-episode__text">
                    <strong>{epTitle}</strong>
                    <span className="m-episode__meta">
                      {ep.downloaded && (
                        <span title="Heruntergeladen" aria-label="Heruntergeladen">
                          <MIcon name="downloadDone" size={14} />
                        </span>
                      )}
                      {p?.completed ? (
                        <span className="m-accent">Gesehen</span>
                      ) : p && p.duration_seconds > 0 ? (
                        <span>{Math.round((p.position_seconds / p.duration_seconds) * 100)} % gesehen</span>
                      ) : (
                        <span className="m-muted2">{sortLanguages(ep.available_languages ?? []).map(shortLanguageLabel).join(' · ')}</span>
                      )}
                    </span>
                    {p && !p.completed && p.duration_seconds > 0 && (
                      <ProgressLine fraction={p.position_seconds / p.duration_seconds} className="m-episode__progress" />
                    )}
                  </span>
                </button>
                {cast.target ? (
                  <div className="m-episode__more">
                    <button type="button" className="m-icon-btn" aria-label="Optionen" onClick={() => setMenuFor(menuFor === ep.url ? null : ep.url)}>
                      <MIcon name="more" />
                    </button>
                    {menuFor === ep.url && (
                      <div className="m-menu m-menu--right">
                        <button
                          type="button"
                          onClick={() => {
                            setMenuFor(null)
                            play(item(ep))
                          }}
                        >
                          <MIcon name="tv" size={18} /> Auf {cast.target.name} abspielen
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setMenuFor(null)
                            play(item(ep), true)
                          }}
                        >
                          <MIcon name="phone" size={18} /> Auf diesem Handy abspielen
                        </button>
                      </div>
                    )}
                  </div>
                ) : (
                  <span className="m-accent m-episode__play" aria-hidden="true">
                    <MIcon name="play" />
                  </span>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </>
  )
}
