import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';
import '../widgets/tv_poster_grid.dart';

enum GridKind { series, anime }

enum _Sort { all, neu, trend }

// ── Display row types ────────────────────────────────────────────────────────

sealed class _Row {}

class _LetterRow extends _Row {
  final String letter;
  _LetterRow(this.letter);
}

class _GridRow extends _Row {
  final int navRow;
  final List<SeriesResult> items;
  _GridRow(this.navRow, this.items);
}

// ── Screen ───────────────────────────────────────────────────────────────────

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
  int _cols = 5;
  static const _perPage = 25;

  _Sort _sort = _Sort.all;

  // "Alle" mode — paginated data
  final _allItems = <SeriesResult>[];
  int _allPage = 0;
  bool _allLoading = false;
  bool _allHasMore = true;
  int _allTotal = 0;

  String? _selectedGenre;

  // Populated from unfiltered loads — never cleared so chips stay visible
  // even while a genre filter is active and _allItems is reloading.
  final _allGenres = <String>[];

  final _scrollCtrl = ScrollController();

  // navRow → GlobalKey (set in build, keyed by navRow index)
  final _rowKeys = <int, GlobalKey>{};
  int _lastScrollRow = -1;

  static const _sortLabels = ['Alle', 'Neu', 'Trend'];

  @override
  void initState() {
    super.initState();
    widget.nav.addListener(_onNavChanged);
    _scrollCtrl.addListener(_onScroll);
    // Kick off first page load immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    widget.nav.removeListener(_onNavChanged);
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadMore() async {
    if (!mounted) return;
    if (_sort != _Sort.all) return;
    if (_allLoading || !_allHasMore) return;
    setState(() => _allLoading = true);

    final api = ref.read(apiServiceProvider);
    try {
      final result = widget.kind == GridKind.anime
          ? await api.getAllAnimes(_allPage + 1, perPage: _perPage, genre: _selectedGenre)
          : await api.getAllSeries(_allPage + 1, perPage: _perPage, genre: _selectedGenre);

      // Backend always returns the full genre list regardless of page/filter.
      // Merge any new genres into _allGenres so the chips are always complete.
      for (final g in result.allGenres) {
        if (!_allGenres.contains(g)) _allGenres.add(g);
      }
      if (result.allGenres.isNotEmpty) _allGenres.sort();
      setState(() {
        _allItems.addAll(result.items);
        _allPage++;
        _allHasMore = result.hasMore;
        _allTotal = result.total;
        _allLoading = false;
      });
    } catch (_) {
      // Stop retrying on hard errors (e.g. 404 — endpoint not yet available)
      setState(() {
        _allLoading = false;
        _allHasMore = false;
      });
    }
  }

  void _resetAllMode() {
    _allItems.clear();
    _allPage = 0;
    _allLoading = false;
    _allHasMore = true;
    _allTotal = 0;
    _selectedGenre = null;
    _rowKeys.clear();
    _lastScrollRow = -1;
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_sort != _Sort.all || !_allHasMore || _allLoading) return;
    final pos = _scrollCtrl.position;
    // maxScrollExtent == 0 means no content yet — don't trigger
    if (pos.maxScrollExtent < 100) return;
    if (pos.pixels >= pos.maxScrollExtent - 1000) _loadMore();
  }

  // ── Nav events ───────────────────────────────────────────────────────────

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

    // Both the sort-tab row (0) and genre-chip row (1) are in the FilterSection
    // at the top of the list — scroll to the very top for both.
    if (navRow == 0 || navRow == 1) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      return;
    }

    final ctx = _rowKeys[navRow]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.1);
    }
  }

  // ── Build helpers ────────────────────────────────────────────────────────

  List<_Row> _buildAllRows({required int gridStartNavRow}) {
    // Backend filters by genre server-side, so _allItems already contains only matching items.
    final source = _allItems;

    final groups = <String, List<SeriesResult>>{};
    for (final item in source) {
      final first = item.title.isEmpty ? '#' : item.title[0].toUpperCase();
      final key = RegExp(r'^[A-Z]$').hasMatch(first) ? first : '#';
      (groups[key] ??= []).add(item);
    }

    const letterOrder = [
      'A','B','C','D','E','F','G','H','I','J','K','L','M',
      'N','O','P','Q','R','S','T','U','V','W','X','Y','Z','#',
    ];
    final sortedKeys = letterOrder.where(groups.containsKey).toList();

    var navRow = gridStartNavRow;
    final rows = <_Row>[];
    for (final letter in sortedKeys) {
      rows.add(_LetterRow(letter));
      final letterItems = groups[letter]!;
      for (var i = 0; i < letterItems.length; i += _cols) {
        final chunk = letterItems.sublist(i, min(i + _cols, letterItems.length));
        rows.add(_GridRow(navRow++, chunk));
      }
    }
    return rows;
  }

  List<_Row> _buildFlatRows(List<SeriesResult> items) {
    var navRow = 1; // row 0 = sort tabs only, no genre row
    final rows = <_Row>[];
    for (var i = 0; i < items.length; i += _cols) {
      final chunk = items.sublist(i, min(i + _cols, items.length));
      rows.add(_GridRow(navRow++, chunk));
    }
    return rows;
  }

  List<SeriesResult> _neuTrendItems(BrowseState state) {
    final List<SeriesResult> raw;
    if (widget.kind == GridKind.anime) {
      raw = _sort == _Sort.neu ? state.newAnimes : state.popularAnimes;
    } else {
      raw = _sort == _Sort.neu ? state.newSeries : state.popularSeries;
    }
    final seen = <String>{};
    return raw.where((e) => seen.add(e.url)).toList();
  }

  // ── Main build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final newCols = TvPosterGrid.calcCols(constraints.maxWidth);
      if (newCols != _cols) {
        _cols = newCols;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return _buildBody(context);
    });
  }

  Widget _buildBody(BuildContext context) {
    final browse = ref.watch(browseProvider);

    // Genres are a separate nav row only in Alle mode when they exist
    final genres = _sort == _Sort.all ? _allGenres : <String>[];
    final hasGenreRow = genres.isNotEmpty;
    final gridStartNavRow = hasGenreRow ? 2 : 1;

    final List<_Row> rows;
    final bool loading;
    if (_sort == _Sort.all) {
      rows = _buildAllRows(gridStartNavRow: gridStartNavRow);
      loading = _allLoading && _allItems.isEmpty;
    } else {
      final items = _neuTrendItems(browse);
      rows = _buildFlatRows(items);
      loading = browse.loading && items.isEmpty;
    }

    // Collect grid rows for nav registration
    final gridRows = rows.whereType<_GridRow>().toList();
    final navLengths = <int>[
      _sortLabels.length,                     // row 0: sort tabs
      if (hasGenreRow) genres.length,          // row 1: genre chips (Alle only)
      ...gridRows.map((r) => r.items.length),  // row 1/2+: grid
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav(
        navLengths,
        (row, col) {
          if (row == 0) {
            // Sort tab
            final newSort = _Sort.values[col];
            if (newSort != _sort) {
              setState(() {
                _sort = newSort;
                if (_sort == _Sort.all) _resetAllMode();
              });
              if (_sort == _Sort.all) _loadMore();
            }
          } else if (hasGenreRow && row == 1) {
            // Genre chip — toggle and reload from page 1
            final genre = genres[col];
            final next = _selectedGenre == genre ? null : genre;
            setState(() {
              _selectedGenre = next;
              _allItems.clear();
              _allPage = 0;
              _allHasMore = true;
              _rowKeys.clear();
              _lastScrollRow = -1;
            });
            _loadMore();
          } else {
            final gridRow = gridRows.firstWhere(
                (r) => r.navRow == row,
                orElse: () => gridRows.last);
            if (col < gridRow.items.length) {
              widget.onSelect(gridRow.items[col]);
            }
          }
        },
        gridMode: true,
      );
      _scrollToNavRow(widget.nav.contentRow);
    });

    final isAnime = widget.kind == GridKind.anime;
    final eyebrow = isAnime ? 'ANIME-KATALOG' : 'SERIEN-KATALOG';
    final headline = isAnime ? 'Alle Anime' : 'Alle Serien';
    final count = _sort == _Sort.all ? _allTotal : gridRows.fold(0, (s, r) => s + r.items.length);

    return loading
        ? const Center(
            child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2))
        : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 80),
            // +2 for header + filter, +1 for bottom loader, +rows
            itemCount: 2 + rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _GridHeader(
                    eyebrow: eyebrow, headline: headline, count: count);
              }
              if (index == 1) {
                return _FilterSection(
                  key: _rowKeys.putIfAbsent(0, GlobalKey.new),
                  sortLabels: _sortLabels,
                  selectedSort: _sort,
                  genres: genres,
                  selectedGenre: _selectedGenre,
                  nav: widget.nav,
                  genreNavRow: hasGenreRow ? 1 : -1,
                  onSortTap: (newSort) {
                    if (newSort == _sort) return;
                    setState(() {
                      _sort = newSort;
                      if (_sort == _Sort.all) _resetAllMode();
                    });
                    if (_sort == _Sort.all) _loadMore();
                  },
                  onGenreTap: (genre) {
                    final next = _selectedGenre == genre ? null : genre;
                    setState(() {
                      _selectedGenre = next;
                      _allItems.clear();
                      _allPage = 0;
                      _allHasMore = true;
                      _rowKeys.clear();
                      _lastScrollRow = -1;
                    });
                    _loadMore();
                  },
                );
              }

              final ri = index - 2;
              if (ri >= rows.length) {
                // Only show spinner while actively loading more
                return _sort == _Sort.all && _allLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Rs.accent, strokeWidth: 2),
                        ),
                      )
                    : const SizedBox.shrink();
              }

              final row = rows[ri];

              if (row is _LetterRow) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(44, 28, 44, 10),
                  child: Row(
                    children: [
                      Text(
                        row.letter,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Rs.accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(height: 1, color: Rs.line),
                      ),
                    ],
                  ),
                );
              }

              final gridRow = row as _GridRow;
              return Padding(
                key: _rowKeys.putIfAbsent(gridRow.navRow, GlobalKey.new),
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_cols, (ci) {
                    final hasItem = ci < gridRow.items.length;
                    return [
                      if (ci > 0) const SizedBox(width: 14),
                      Expanded(
                        child: hasItem
                            ? AspectRatio(
                                aspectRatio: 2 / 3,
                                child: ListenableBuilder(
                                  listenable: widget.nav,
                                  builder: (_, _) => _LazyPosterCard(
                                    item: gridRow.items[ci],
                                    focused: widget.nav.isItemFocused(
                                        gridRow.navRow, ci),
                                    onTap: () =>
                                        widget.onSelect(gridRow.items[ci]),
                                  ),
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ];
                  }).expand((e) => e).toList(),
                ),
              );
            },
          );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

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
            count > 0
                ? '$count Titel · alphabetisch sortiert'
                : 'Lade Katalog …',
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
  final List<String> genres;       // empty → hidden (Neu/Trend mode)
  final String? selectedGenre;
  final AppNavController nav;
  final void Function(_Sort) onSortTap;
  final void Function(String) onGenreTap;
  // Nav row index for genre chips; -1 means no separate genre row (Neu/Trend)
  final int genreNavRow;

  const _FilterSection({
    super.key,
    required this.sortLabels,
    required this.selectedSort,
    required this.genres,
    required this.selectedGenre,
    required this.nav,
    required this.onSortTap,
    required this.onGenreTap,
    this.genreNavRow = -1,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nav,
      builder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Sort tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 18, 44, 0),
            child: Row(
              children: List.generate(sortLabels.length, (i) {
                final isFoc = nav.isItemFocused(0, i);
                final isOn = selectedSort == _Sort.values[i];
                return Padding(
                  padding: EdgeInsets.only(right: i < sortLabels.length - 1 ? 10 : 0),
                  child: _Chip(
                    label: sortLabels[i],
                    focused: isFoc,
                    active: isOn,
                    activeColor: Rs.accent,
                    onTap: () => onSortTap(_Sort.values[i]),
                  ),
                );
              }),
            ),
          ),
          // Row 2: Genre chips (only in Alle mode)
          if (genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 10, 44, 0),
              child: Wrap(
                spacing: 9,
                runSpacing: 9,
                children: List.generate(genres.length, (i) {
                  final isFoc = genreNavRow >= 0 && nav.isItemFocused(genreNavRow, i);
                  final isOn = selectedGenre == genres[i];
                  return _Chip(
                    label: genres[i],
                    focused: isFoc,
                    active: isOn,
                    activeColor: const Color(0xFF4B7FD9),
                    onTap: () => onGenreTap(genres[i]),
                  );
                }),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool focused;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.focused,
    required this.active,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? activeColor
            : focused
                ? activeColor.withValues(alpha: 0.18)
                : Rs.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: focused || active ? activeColor : Rs.line,
          width: focused || active ? 2 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active
              ? Colors.white
              : focused
                  ? activeColor
                  : Rs.muted,
        ),
      ),
    ),
    );
  }
}

// ── Lazy poster card ─────────────────────────────────────────────────────────

/// Shows a [RsPosterCard] and lazily fetches the TMDB poster when [item.posterUrl]
/// is empty. Results are stored in a static cache so each title is only fetched once
/// across the entire app session.
class _LazyPosterCard extends ConsumerStatefulWidget {
  final SeriesResult item;
  final bool focused;
  final VoidCallback? onTap;

  const _LazyPosterCard({
    required this.item,
    required this.focused,
    this.onTap,
  });

  @override
  ConsumerState<_LazyPosterCard> createState() => _LazyPosterCardState();
}

class _LazyPosterCardState extends ConsumerState<_LazyPosterCard> {
  // Shared across all instances so each title is fetched only once per session.
  static final _cache = <String, String>{};

  String? _posterUrl;

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.item.title];
    if (cached != null) {
      _posterUrl = cached.isNotEmpty ? cached : null;
    } else if (widget.item.posterUrl.isEmpty) {
      _fetchPoster();
    }
  }

  Future<void> _fetchPoster() async {
    final title = widget.item.title;
    _cache[title] = ''; // Mark as in-flight to prevent duplicate requests
    try {
      final url = await ref.read(apiServiceProvider).getTmdbPoster(title);
      _cache[title] = url;
      if (mounted && url.isNotEmpty) {
        setState(() => _posterUrl = url);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final displayItem = _posterUrl != null
        ? SeriesResult(
            title: widget.item.title,
            url: widget.item.url,
            posterUrl: _posterUrl!,
          )
        : widget.item;

    return RsPosterCard(
      item: displayItem,
      focused: widget.focused,
      inGrid: true,
      onTap: widget.onTap,
    );
  }
}
