import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';
import '../widgets/tv_poster_grid.dart';

enum _WatchlistSort { recentlyWatched, newContent, alphabetical }

class WatchlistScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;

  const WatchlistScreen({super.key, required this.nav, required this.onSelect});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  int _cols = 5;
  final _scrollCtrl = ScrollController();
  _WatchlistSort _sort = _WatchlistSort.recentlyWatched;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(watchlistEnrichedProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<WatchlistEntry> _sorted(List<WatchlistEntry> items) {
    final sorted = List<WatchlistEntry>.from(items);
    switch (_sort) {
      case _WatchlistSort.recentlyWatched:
        sorted.sort((a, b) {
          final at = a.lastWatchedAt;
          final bt = b.lastWatchedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      case _WatchlistSort.newContent:
        sorted.sort((a, b) {
          final aNew = a.newContent != null ? 0 : 1;
          final bNew = b.newContent != null ? 0 : 1;
          if (aNew != bNew) return aNew - bNew;
          final at = a.lastWatchedAt;
          final bt = b.lastWatchedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      case _WatchlistSort.alphabetical:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchlistEnrichedProvider);

    return state.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2),
      ),
      error: (e, _) => Center(
        child: Text('Fehler: $e',
            style: const TextStyle(color: Rs.muted, fontSize: 16)),
      ),
      data: (items) => _buildContent(items),
    );
  }

  Widget _buildContent(List<WatchlistEntry> items) {
    return LayoutBuilder(builder: (_, constraints) {
      final newCols = TvPosterGrid.calcCols(constraints.maxWidth);
      if (newCols != _cols) {
        _cols = newCols;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return _buildList(items);
    });
  }

  Widget _buildList(List<WatchlistEntry> items) {
    final sortedItems = _sorted(items);
    final seriesItems = sortedItems.map((e) => e.asSeriesResult).toList();
    final entryMap = {for (final e in sortedItems) e.url: e};

    // progress map from continueWatchingProvider
    final continueState = ref.watch(continueWatchingProvider);
    final progressMap = <String, double>{};
    for (final p in continueState.items) {
      final url = p.seriesUrl ?? '';
      if (url.isNotEmpty && p.durationSeconds > 0) {
        progressMap[url] = (p.positionSeconds / p.durationSeconds).clamp(0.0, 1.0);
      }
    }

    // Register nav: row 0 = sort chips (3), rows 1+ = grid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final gridRowLengths = sortedItems.isEmpty
          ? <int>[]
          : TvPosterGrid.rowLengthsFor(seriesItems, _cols);
      final allLengths = [3, ...gridRowLengths];
      widget.nav.registerNav(allLengths, (row, col) {
        if (row == 0) {
          setState(() => _sort = _WatchlistSort.values[col]);
        } else {
          final index = (row - 1) * _cols + col;
          if (index >= 0 && index < sortedItems.length) {
            widget.onSelect(sortedItems[index].asSeriesResult);
          }
        }
      }, gridMode: true);
    });

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // ── Header ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 40, 44, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 28,
                decoration: BoxDecoration(
                  color: Rs.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 13),
              const Text(
                'Watchlist',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Rs.text,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 16),
              if (items.isNotEmpty)
                Text(
                  '${items.length} Titel',
                  style: const TextStyle(fontSize: 16, color: Rs.muted),
                ),
            ],
          ),
        ),

        // ── Sort chips ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 16, 44, 0),
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) => Row(
              children: [
                _SortChip(
                  label: 'Zuletzt angeschaut',
                  icon: Icons.history_rounded,
                  selected: _sort == _WatchlistSort.recentlyWatched,
                  focused: widget.nav.isItemFocused(0, 0),
                  onTap: () => setState(() => _sort = _WatchlistSort.recentlyWatched),
                ),
                const SizedBox(width: 10),
                _SortChip(
                  label: 'Neue Folgen',
                  icon: Icons.fiber_new_rounded,
                  selected: _sort == _WatchlistSort.newContent,
                  focused: widget.nav.isItemFocused(0, 1),
                  onTap: () => setState(() => _sort = _WatchlistSort.newContent),
                ),
                const SizedBox(width: 10),
                _SortChip(
                  label: 'A–Z',
                  icon: Icons.sort_by_alpha_rounded,
                  selected: _sort == _WatchlistSort.alphabetical,
                  focused: widget.nav.isItemFocused(0, 2),
                  onTap: () => setState(() => _sort = _WatchlistSort.alphabetical),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Empty state ────────────────────────────────────────────────────────
        if (sortedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border_rounded,
                    color: Rs.muted2.withValues(alpha: 0.45),
                    size: 72,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Noch keine Serien in der Watchlist',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Rs.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Füge Serien über die Detailseite hinzu',
                    style: TextStyle(fontSize: 14, color: Rs.muted2),
                  ),
                ],
              ),
            ),
          )
        else
          // ── Poster grid with badges ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TvPosterGrid(
              nav: widget.nav,
              items: seriesItems,
              cols: _cols,
              navRowOffset: 1,
              progressMap: progressMap,
              onSelect: widget.onSelect,
              itemBuilder: (item, focused, onTap) {
                final entry = entryMap[item.url];
                final badge = entry?.newContent;
                return Stack(
                  children: [
                    RsPosterCard(
                      item: item,
                      focused: focused,
                      inGrid: true,
                      progressFraction: progressMap[item.url],
                      onTap: onTap,
                    ),
                    if (badge != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: badge == 'season'
                                ? const Color(0xFF4CAF50)
                                : Rs.accent,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Text(
                            badge == 'season' ? 'NEUE STAFFEL' : 'NEUE FOLGE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

// ── Sort chip widget ──────────────────────────────────────────────────────────

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Rs.accent
              : focused
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: focused && !selected
                ? Rs.accent.withValues(alpha: 0.7)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? Colors.white : Rs.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Rs.muted,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
