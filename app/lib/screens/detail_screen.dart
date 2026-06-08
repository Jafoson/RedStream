import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/tv_focusable.dart';
import 'download_play_screen.dart';

/// Combined series detail + episode list, matching the RedStream detail screen.
/// Pushed via Navigator.push — handles its own D-Pad navigation independently
/// of the AppNavController (which is paused while this route is active).
class DetailScreen extends ConsumerStatefulWidget {
  final String seriesUrl;
  final String title;

  const DetailScreen({
    super.key,
    required this.seriesUrl,
    required this.title,
  });

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  SeriesDetail? _detail;
  List<Season> _seasons = [];
  List<Episode> _episodes = [];
  int _selectedSeason = 0;
  bool _loading = true;
  bool _episodesLoading = false;
  String? _error;
  WatchProgress? _resumeProgress;
  bool _resumeIsNextEp = false;
  bool _inWatchlist = false;
  int? _autosyncJobId;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  void _computeResume(List<WatchProgress> allProgress) {
    final forSeries = allProgress
        .where((p) => p.seriesUrl == widget.seriesUrl)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final last = forSeries.firstOrNull;
    if (last == null) {
      _resumeProgress = null;
      _resumeIsNextEp = false;
      return;
    }
    if (last.completed) {
      _resumeProgress = last;
      _resumeIsNextEp = true;
    } else {
      final inProgress = forSeries
          .where((p) => !p.completed && p.positionSeconds > 30)
          .firstOrNull;
      _resumeProgress = inProgress ?? last;
      _resumeIsNextEp = _resumeProgress?.completed ?? false;
    }
  }

  Future<void> _loadDetail() async {
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getSeriesDetail(widget.seriesUrl),
        api.getSeasons(widget.seriesUrl),
        api.getAllProgress(limit: 100),
        api.isInWatchlist(widget.seriesUrl).catchError((_) => false),
        api.checkAutosync(widget.seriesUrl).then<int?>((v) => v).catchError((_) => null as int?),
      ]);
      if (!mounted) return;
      final allProgress = results[2] as List<WatchProgress>;
      _computeResume(allProgress);
      setState(() {
        _detail = results[0] as SeriesDetail;
        _seasons = results[1] as List<Season>;
        _inWatchlist = results[3] as bool;
        _autosyncJobId = results[4] as int?;
        _loading = false;
      });
      if (_seasons.isNotEmpty) _loadEpisodes(_seasons[0], prefetch: true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleWatchlist() async {
    final api = ref.read(apiServiceProvider);
    final title = _detail?.title ?? widget.title;
    try {
      if (_inWatchlist) {
        await api.removeFromWatchlist(widget.seriesUrl);
        if (mounted) setState(() => _inWatchlist = false);
        if (_autosyncJobId case final id?) {
          try { await api.removeAutosync(id); } catch (_) {}
          if (mounted) setState(() => _autosyncJobId = null);
        }
      } else {
        await api.addToWatchlist(
          widget.seriesUrl,
          title: title,
          posterUrl: _detail?.posterUrl ?? '',
        );
        if (mounted) setState(() => _inWatchlist = true);
        if (_autosyncJobId == null) {
          try {
            final id = await api.addAutosync(widget.seriesUrl, title: title);
            if (mounted) setState(() => _autosyncJobId = id);
          } catch (_) {}
        }
      }
      ref.read(watchlistProvider.notifier).refresh();
    } catch (_) {}
  }

  Future<void> _ensureInWatchlist() async {
    if (_inWatchlist) return;
    final api = ref.read(apiServiceProvider);
    final title = _detail?.title ?? widget.title;
    final poster = _detail?.posterUrl ?? '';
    try {
      await api.addToWatchlist(widget.seriesUrl, title: title, posterUrl: poster);
      if (mounted) setState(() => _inWatchlist = true);
    } catch (_) {}
    if (_autosyncJobId == null) {
      try {
        final id = await api.addAutosync(widget.seriesUrl, title: title);
        if (mounted) setState(() => _autosyncJobId = id);
      } catch (_) {}
    }
    ref.read(watchlistProvider.notifier).refresh();
  }

  Future<void> _loadEpisodes(Season season, {bool prefetch = false}) async {
    setState(() => _episodesLoading = true);
    try {
      final eps = await ref.read(apiServiceProvider).getEpisodes(season.url);
      if (mounted) setState(() { _episodes = eps; _episodesLoading = false; });
      if (prefetch && eps.isNotEmpty) _prefetchFirstEpisode(season, eps.first);
    } catch (_) {
      if (mounted) setState(() => _episodesLoading = false);
    }
  }

  Future<void> _prefetchFirstEpisode(Season season, Episode ep) async {
    final api = ref.read(apiServiceProvider);
    try {
      final library = await api.getLibrary();
      for (final title in library) {
        final nFolder = title.folder.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final nSeries = widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (!nFolder.contains(nSeries) && !nSeries.contains(nFolder)) continue;
        final url = await api.getStreamUrl(
          folder: title.folder,
          season: season.seasonNumber,
          episode: ep.episodeNumber,
        );
        if (url.isNotEmpty) return; // already downloaded
      }
    } catch (_) {}
    // Not in library → enqueue silently
    try {
      final lang = ep.availableLanguages.contains('German Dub')
          ? 'German Dub'
          : (ep.availableLanguages.firstOrNull ?? 'German Dub');
      await api.enqueueDownload(
        title: widget.title,
        seriesUrl: widget.seriesUrl,
        episodeUrls: [ep.url],
        language: lang,
        provider: 'VOE',
      );
    } catch (_) {}
  }

  void _selectSeason(int index) {
    if (index == _selectedSeason) return;
    setState(() { _selectedSeason = index; _episodes = []; });
    _loadEpisodes(_seasons[index]);
  }

  Future<void> _refreshProgress() async {
    if (!mounted) return;
    try {
      final allProgress = await ref
          .read(apiServiceProvider)
          .getAllProgress(limit: 500);
      if (!mounted) return;

      _computeResume(allProgress);

      // Patch episode watch data locally — no re-fetch needed
      final byUrl = {for (final p in allProgress) p.episodeUrl: p};
      final updatedEpisodes = _episodes.map((ep) {
        final prog = byUrl[ep.url];
        if (prog == null) return ep;
        return ep.copyWith(
          watchPosition: prog.positionSeconds,
          watchDuration: prog.durationSeconds,
          isWatched: prog.completed,
        );
      }).toList();

      setState(() => _episodes = updatedEpisodes);
    } catch (_) {}
  }

  void _playEpisode(Episode ep) {
    _ensureInWatchlist();
    final api = ref.read(apiServiceProvider);
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => DownloadPlayScreen(
            api: api,
            episodeUrl: ep.url,
            seriesUrl: widget.seriesUrl,
            seriesTitle: widget.title,
            season: _seasons[_selectedSeason].seasonNumber,
            episodeNumber: ep.episodeNumber,
            episodeTitle: ep.displayTitle,
            availableLanguages: ep.availableLanguages,
          ),
        ))
        .then((_) => _refreshProgress());
  }

  void _playFirstEpisode() {
    if (_episodes.isNotEmpty) _playEpisode(_episodes.first);
  }

  void _playFromResume() {
    final prog = _resumeProgress;
    if (prog == null) { _playFirstEpisode(); return; }
    final api = ref.read(apiServiceProvider);

    if (_resumeIsNextEp) {
      // Last watched was fully completed → play the next episode
      final nextNum = prog.episodeNumber + 1;
      final nextEp = _episodes.where((e) => e.episodeNumber == nextNum).firstOrNull;
      final derivedUrl = prog.episodeUrl.replaceAllMapped(
        RegExp(r'episode-(\d+)'),
        (_) => 'episode-$nextNum',
      );
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => DownloadPlayScreen(
              api: api,
              episodeUrl: nextEp?.url ?? (derivedUrl != prog.episodeUrl ? derivedUrl : ''),
              seriesUrl: widget.seriesUrl,
              seriesTitle: widget.title,
              season: prog.season,
              episodeNumber: nextNum,
              episodeTitle: nextEp?.displayTitle ?? 'Folge $nextNum',
              availableLanguages: nextEp?.availableLanguages ?? [],
            ),
          ))
          .then((_) => _refreshProgress());
      return;
    }

    final ep = _episodes.where((e) => e.episodeNumber == prog.episodeNumber).firstOrNull;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => DownloadPlayScreen(
            api: api,
            episodeUrl: prog.episodeUrl,
            seriesUrl: widget.seriesUrl,
            seriesTitle: widget.title,
            season: prog.season,
            episodeNumber: prog.episodeNumber,
            episodeTitle: ep?.displayTitle ?? prog.episodeTitle ?? 'Folge ${prog.episodeNumber}',
            availableLanguages: ep?.availableLanguages ?? [],
          ),
        ))
        .then((_) => _refreshProgress());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.backspace ||
                event.logicalKey == LogicalKeyboardKey.goBack)) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Rs.bg,
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2))
            : _error != null
                ? _ErrorBody(error: _error!, onBack: () => Navigator.of(context).pop())
                : _DetailBody(
                    detail: _detail!,
                    seasons: _seasons,
                    episodes: _episodes,
                    selectedSeason: _selectedSeason,
                    episodesLoading: _episodesLoading,
                    resumeProgress: _resumeProgress,
                    resumeIsNextEp: _resumeIsNextEp,
                    onBack: () => Navigator.of(context).pop(),
                    onSelectSeason: _selectSeason,
                    onPlayEpisode: _playEpisode,
                    onPlay: _playFirstEpisode,
                    onResume: _playFromResume,
                    inWatchlist: _inWatchlist,
                    onToggleWatchlist: _toggleWatchlist,
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail body — hero + episode list
// ─────────────────────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final SeriesDetail detail;
  final List<Season> seasons;
  final List<Episode> episodes;
  final int selectedSeason;
  final bool episodesLoading;
  final WatchProgress? resumeProgress;
  final bool resumeIsNextEp;
  final VoidCallback onBack;
  final void Function(int index) onSelectSeason;
  final void Function(Episode ep) onPlayEpisode;
  final VoidCallback onPlay;
  final VoidCallback onResume;
  final bool inWatchlist;
  final VoidCallback onToggleWatchlist;

  const _DetailBody({
    required this.detail,
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    required this.episodesLoading,
    this.resumeProgress,
    this.resumeIsNextEp = false,
    required this.onBack,
    required this.onSelectSeason,
    required this.onPlayEpisode,
    required this.onPlay,
    required this.onResume,
    required this.inWatchlist,
    required this.onToggleWatchlist,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Hero section ────────────────────────────────────────────────────
        _HeroSection(
          detail: detail,
          onBack: onBack,
          onPlay: onPlay,
          resumeProgress: resumeProgress,
          resumeIsNextEp: resumeIsNextEp,
          onResume: onResume,
          inWatchlist: inWatchlist,
          onToggleWatchlist: onToggleWatchlist,
        ),

        // ── Season tabs ─────────────────────────────────────────────────────
        if (seasons.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(64, 28, 64, 6),
            child: _SectionBar('Folgen'),
          ),
          _SeasonBar(
            seasons: seasons,
            selected: selectedSeason,
            onSelect: onSelectSeason,
          ),
        ],

        // ── Episode list ────────────────────────────────────────────────────
        if (episodesLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 16, 64, 60),
            child: Column(
              children: episodes
                  .map((ep) => _EpisodeRow(
                        ep: ep,
                        detail: detail,
                        onPlay: () => onPlayEpisode(ep),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  final SeriesDetail detail;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final WatchProgress? resumeProgress;
  final bool resumeIsNextEp;
  final VoidCallback onResume;
  final bool inWatchlist;
  final VoidCallback onToggleWatchlist;

  const _HeroSection({
    required this.detail,
    required this.onBack,
    required this.onPlay,
    this.resumeProgress,
    this.resumeIsNextEp = false,
    required this.onResume,
    required this.inWatchlist,
    required this.onToggleWatchlist,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 560,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background artwork — prefer wide backdrop, fall back to poster
          if (detail.backdropUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: detail.backdropUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) => Container(color: Rs.panel2),
              errorWidget: (_, _, _) => Container(color: Rs.panel2),
            )
          else if (detail.posterUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: detail.posterUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) => Container(color: Rs.panel2),
              errorWidget: (_, _, _) => Container(color: Rs.panel2),
            )
          else
            Container(color: Rs.panel2),

          // Gradient overlay — dark on left, fades right
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.0, 0.4, 0.75],
                colors: [Color(0xF517120E), Color(0xB817120E), Color(0x3317120E)],
              ),
            ),
          ),
          // Bottom fade
          const Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Rs.bg, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 28,
            left: 44,
            child: TvFocusable(
              autofocus: false,
              onActivate: onBack,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Rs.line),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Zurück',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

          // Content — bottom left
          Positioned(
            left: 64,
            bottom: 36,
            right: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  detail.title,
                  style: const TextStyle(
                    fontSize: 62,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -2.0,
                    height: 0.97,
                    shadows: [Shadow(color: Color(0x88000000), blurRadius: 24)],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                // Meta chips
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (detail.releaseYear.isNotEmpty)
                      _MetaChip(detail.releaseYear),
                    ...detail.genres.map(_GenreTag.new),
                  ],
                ),
                if (detail.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    detail.description,
                    style: const TextStyle(
                      fontSize: 17,
                      color: Color(0xFFD7D8DA),
                      height: 1.5,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 22),
                // Action buttons
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TvFocusable(
                      autofocus: true,
                      onActivate: resumeProgress != null ? onResume : onPlay,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          color: resumeProgress != null ? Colors.white : Rs.accent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              resumeProgress != null
                                  ? Icons.play_circle_outline_rounded
                                  : Icons.play_arrow_rounded,
                              color: resumeProgress != null ? Colors.black : Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              resumeProgress != null
                                  ? resumeIsNextEp
                                      ? 'Nächste Folge E${resumeProgress!.episodeNumber + 1}'
                                      : 'Fortsetzen E${resumeProgress!.episodeNumber}'
                                  : 'Abspielen',
                              style: TextStyle(
                                  color: resumeProgress != null ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (resumeProgress != null)
                      TvFocusable(
                        onActivate: onPlay,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Rs.line2),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.skip_previous_rounded, color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text('Von vorne',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17)),
                            ],
                          ),
                        ),
                      ),
                    if (resumeProgress != null) const SizedBox(width: 12),
                    TvFocusable(
                      onActivate: onToggleWatchlist,
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          color: inWatchlist
                              ? Rs.accent.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inWatchlist ? Rs.accent : Rs.line2,
                            width: inWatchlist ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              inWatchlist
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_border_rounded,
                              color: inWatchlist ? Rs.accent : Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              inWatchlist ? 'In meiner Liste' : 'Meine Liste',
                              style: TextStyle(
                                color: inWatchlist ? Rs.accent : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Rs.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Rs.gold, fontSize: 14, fontWeight: FontWeight.w800)),
    );
  }
}

class _GenreTag extends StatelessWidget {
  final String genre;
  const _GenreTag(this.genre);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Rs.line2),
      ),
      child: Text(genre,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

class _SectionBar extends StatelessWidget {
  final String title;
  const _SectionBar(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5, height: 24,
          decoration: BoxDecoration(
            color: Rs.accent, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 13),
        Text(title,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Rs.text,
                letterSpacing: -0.5)),
      ],
    );
  }
}

class _SeasonBar extends StatelessWidget {
  final List<Season> seasons;
  final int selected;
  final void Function(int) onSelect;
  const _SeasonBar(
      {required this.seasons, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(64, 22, 64, 6),
      child: Row(
        children: List.generate(seasons.length, (i) {
          final isOn = i == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TvFocusable(
              onActivate: () => onSelect(i),
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: isOn
                      ? Rs.accent.withValues(alpha: 0.18)
                      : Rs.panel2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: isOn
                        ? Rs.accent.withValues(alpha: 0.5)
                        : Rs.line,
                  ),
                ),
                child: Text(
                  seasons[i].label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isOn ? Colors.white : Rs.muted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final Episode ep;
  final SeriesDetail detail;
  final VoidCallback onPlay;
  const _EpisodeRow({required this.ep, required this.detail, required this.onPlay});

  static String _fmtSeconds(double s) {
    final t = Duration(milliseconds: (s * 1000).round());
    final h = t.inHours;
    final m = t.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = t.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TvFocusable(
        onActivate: onPlay,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Rs.panel2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Rs.line),
          ),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 180,
                  height: 102,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ep.previewUrl != null && ep.previewUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ep.previewUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: Rs.panel3),
                          errorWidget: (_, _, _) => detail.posterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: detail.posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(color: Rs.panel3),
                                  errorWidget: (_, _, _) => Container(color: Rs.panel3),
                                )
                              : Container(color: Rs.panel3),
                        )
                      else if (detail.posterUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: detail.posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: Rs.panel3),
                          errorWidget: (_, _, _) => Container(color: Rs.panel3),
                        )
                      else
                        Container(color: Rs.panel3),
                      // Dim overlay for watched episodes
                      if (ep.isWatched)
                        Container(color: Colors.black.withValues(alpha: 0.5)),
                      // Episode number badge
                      Positioned(
                        top: 8, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'F${ep.episodeNumber}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      // Watched badge
                      if (ep.isWatched)
                        Positioned(
                          top: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Rs.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text('Gesehen',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      // Progress bar at bottom of thumbnail
                      if (ep.isPartiallyWatched)
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: LinearProgressIndicator(
                            value: ep.watchProgress,
                            backgroundColor: Colors.black38,
                            valueColor: const AlwaysStoppedAnimation<Color>(Rs.accent),
                            minHeight: 4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ep.episodeNumber}. ${ep.displayTitle}',
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Rs.text),
                    ),
                    const SizedBox(height: 6),
                    if (ep.availableLanguages.isNotEmpty)
                      Text(
                        ep.availableLanguages.join(' · '),
                        style: const TextStyle(
                            fontSize: 13, color: Rs.muted, fontWeight: FontWeight.w600),
                      ),
                    if (ep.isPartiallyWatched) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Fortsetzen ab ${_fmtSeconds(ep.watchPosition)}',
                        style: const TextStyle(
                            fontSize: 13, color: Rs.accent, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              // Play / Resume / Watched icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: ep.isWatched
                      ? Rs.accent.withValues(alpha: 0.15)
                      : ep.isPartiallyWatched
                          ? Rs.accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ep.isWatched
                      ? Icons.check_rounded
                      : ep.isPartiallyWatched
                          ? Icons.play_circle_outline_rounded
                          : Icons.play_arrow_rounded,
                  color: ep.isWatched || ep.isPartiallyWatched ? Rs.accent : Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final VoidCallback onBack;
  const _ErrorBody({required this.error, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Rs.muted2, size: 56),
          const SizedBox(height: 16),
          Text(error, style: const TextStyle(color: Rs.muted), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TvFocusable(
            autofocus: true,
            onActivate: onBack,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                  color: Rs.accent, borderRadius: BorderRadius.circular(12)),
              child: const Text('Zurück',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
