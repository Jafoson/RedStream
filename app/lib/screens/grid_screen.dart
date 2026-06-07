import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';

enum GridKind { series, anime }

enum _Sort { all, neu, trend }

const _kGenres = [
  'Action', 'Abenteuer', 'Comedy', 'Drama', 'Fantasy',
  'Horror', 'Mystery', 'Romance', 'Sci-Fi', 'Thriller',
  'Slice of Life', 'Sport', 'Supernatural',
];

/// Full series or anime catalogue with sort tabs, genre chips, and a 5-column grid.
class GridScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final GridKind kind;
  final void Function(SeriesResult) onSelect;

  const GridScreen({
    super.key,
    required this.nav,
    required this.kind,
    required this.onSelect,
  });

  @override
  ConsumerState<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends ConsumerState<GridScreen> {
  static const _cols = 5;
  _Sort _sort = _Sort.all;
  final _scrollCtrl = ScrollController();

  // Per-row GlobalKeys so we can Scrollable.ensureVisible on D-pad Up/Down.
  final _rowKeys = List.generate(80, (_) => GlobalKey());
  int _lastScrollRow = -1;

  // Sort tabs shown in the filter row (D-pad navigable)
  static const _sortLabels = ['Alle', 'Neu', 'Trend'];

  @override
  void initState() {
    super.initState();
    widget.nav.addListener(_onNavChanged);
  }

  @override
  void dispose() {
    widget.nav.removeListener(_onNavChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    final navRow = widget.nav.contentRow;
    if (navRow == _lastScrollRow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollToNavRow(navRow);
    });
  }

  void _scrollToNavRow(int navRow) {
    if (!_scrollCtrl.hasClients) return;
    _lastScrollRow = navRow;
    if (navRow >= _rowKeys.length) return;
    final ctx = _rowKeys[navRow].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 0.1,
      );
    } else {
      _scrollToRowByOffset(navRow);
    }
  }

  void _scrollToRowByOffset(int navRow) {
    if (!_scrollCtrl.hasClients) return;
    const headerH = 148.0;
    const filterH = 120.0;  // sort tabs + genre chips
    const rowH = 320.0;     // approximate portrait card height + padding
    final double target;
    if (navRow == 0) {
      target = 0;
    } else {
      target = headerH + filterH + (navRow - 1) * rowH - 16;
    }
    _scrollCtrl.animateTo(
      target.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  List<SeriesResult> _filteredItems(BrowseState state) {
    final List<SeriesResult> raw;
    if (widget.kind == GridKind.anime) {
      raw = switch (_sort) {
        _Sort.neu   => state.newAnimes,
        _Sort.trend => state.popularAnimes,
        _Sort.all   => [...state.newAnimes, ...state.popularAnimes],
      };
    } else {
      raw = switch (_sort) {
        _Sort.neu   => state.newSeries,
        _Sort.trend => state.popularSeries,
        _Sort.all   => [...state.newSeries, ...state.popularSeries],
      };
    }
    final seen = <String>{};
    return raw.where((e) => seen.add(e.url)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browseProvider);
    final items = _filteredItems(state);

    final gridRows = <List<SeriesResult>>[];
    for (var i = 0; i < items.length; i += _cols) {
      gridRows.add(items.sublist(i, (i + _cols).clamp(0, items.length)));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav(
        [_sortLabels.length, ...gridRows.map((r) => r.length)],
        (row, col) {
          if (row == 0) {
            setState(() => _sort = _Sort.values[col]);
          } else {
            final item = gridRows[row - 1][col];
            widget.onSelect(item);
          }
        },
      );
      _scrollToNavRow(widget.nav.contentRow);
    });

    final isAnime = widget.kind == GridKind.anime;
    final eyebrow = isAnime ? 'ANIME-KATALOG' : 'SERIEN-KATALOG';
    final headline = isAnime ? 'Alle Anime' : 'Alle Serien';

    return state.loading && items.isEmpty
        ? const Center(
            child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2))
        : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 60),
            itemCount: 2 + gridRows.length,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _GridHeader(
                    eyebrow: eyebrow, headline: headline, count: items.length);
              }
              if (index == 1) {
                return _FilterSection(
                  key: _rowKeys[0],
                  sortLabels: _sortLabels,
                  selectedSort: _sort,
                  nav: widget.nav,
                );
              }
              final ri = index - 2;
              final row = gridRows[ri];
              return Padding(
                key: _rowKeys[ri + 1],
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...List.generate(row.length, (ci) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: ci < row.length - 1 ? 14 : 0),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ListenableBuilder(
                            listenable: widget.nav,
                            builder: (_, _) => RsPosterCard(
                              item: row[ci],
                              focused: widget.nav.isItemFocused(ri + 1, ci),
                              inGrid: true,
                              onTap: () => widget.onSelect(row[ci]),
                            ),
                          ),
                        ),
                      ),
                    )),
                    // Fill remaining columns in incomplete last row
                    ...List.generate(_cols - row.length, (_) => const Expanded(child: SizedBox())),
                  ],
                ),
              );
            },
          );
  }
}

class _GridHeader extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final int count;
  const _GridHeader(
      {required this.eyebrow, required this.headline, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 32, 44, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: Rs.accent,
              )),
          const SizedBox(height: 10),
          Text(headline,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: Rs.text,
                letterSpacing: -1.2,
              )),
          const SizedBox(height: 4),
          Text(
            '$count Titel · 4K HDR · wöchentlich neue Folgen',
            style: const TextStyle(fontSize: 15, color: Rs.muted),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final List<String> sortLabels;
  final _Sort selectedSort;
  final AppNavController nav;

  const _FilterSection({
    super.key,
    required this.sortLabels,
    required this.selectedSort,
    required this.nav,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sort tabs row (D-pad navigable)
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 18, 44, 0),
          child: ListenableBuilder(
            listenable: nav,
            builder: (_, _) => Row(
              children: List.generate(sortLabels.length, (i) {
                final label = sortLabels[i];
                final isFoc = nav.isItemFocused(0, i);
                final isOn = selectedSort == _Sort.values[i];
                return Padding(
                  padding: EdgeInsets.only(right: i < sortLabels.length - 1 ? 10 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: isOn
                          ? Rs.accent
                          : isFoc
                              ? Rs.accent.withValues(alpha: 0.18)
                              : Rs.panel2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isFoc ? Rs.accent : (isOn ? Rs.accent : Rs.line),
                        width: isFoc || isOn ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isOn ? Colors.white : (isFoc ? Rs.accent : Rs.muted),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        // Genre chips row (visual only, not D-pad navigable)
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 12, 44, 12),
          child: Wrap(
            spacing: 9,
            runSpacing: 9,
            children: _kGenres.map((g) => _GenreChip(label: g)).toList(),
          ),
        ),
      ],
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  const _GenreChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Rs.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Rs.line, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Rs.muted,
        ),
      ),
    );
  }
}
