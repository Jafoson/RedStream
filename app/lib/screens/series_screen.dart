import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'episodes_screen.dart';

class SeriesScreen extends ConsumerStatefulWidget {
  final String seriesUrl;
  final String title;

  const SeriesScreen({super.key, required this.seriesUrl, required this.title});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  SeriesDetail? _detail;
  List<Season> _seasons = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiServiceProvider);
    try {
      final results = await Future.wait([
        api.getSeriesDetail(widget.seriesUrl),
        api.getSeasons(widget.seriesUrl),
      ]);
      if (mounted) {
        setState(() {
          _detail = results[0] as SeriesDetail;
          _seasons = results[1] as List<Season>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)));
    }

    final detail = _detail!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Poster + metadata ─────────────────────────────────────────────
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: detail.posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: detail.posterUrl,
                                width: 256,
                                height: 384,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 256,
                                height: 384,
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(Icons.movie, size: 64, color: Colors.white24),
                              ),
                      ),
                      const SizedBox(height: 20),
                      Text(detail.title, style: tt.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (detail.releaseYear.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(detail.releaseYear, style: tt.bodyMedium),
                      ],
                      if (detail.genres.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: detail.genres
                              .map((g) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(g, style: TextStyle(fontSize: 12, color: cs.primary)),
                                  ))
                              .toList(),
                        ),
                      ],
                      if (detail.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          detail.description,
                          style: tt.bodyMedium,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Season list ───────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 32, 32, 16),
                child: Text('Seasons', style: tt.displayMedium),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(right: 32, bottom: 32),
                  itemCount: _seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final season = _seasons[i];
                    return TvFocusable(
                      autofocus: i == 0,
                      onActivate: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EpisodesScreen(
                            seasonUrl: season.url,
                            seriesUrl: widget.seriesUrl,
                            seriesTitle: detail.title,
                            season: season,
                          ),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${season.seasonNumber}',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(season.label, style: tt.titleMedium),
                                  Text(
                                    '${season.episodeCount} episode${season.episodeCount == 1 ? '' : 's'}',
                                    style: tt.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: cs.primary, size: 28),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
