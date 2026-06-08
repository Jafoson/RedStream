import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;

  const WatchlistScreen({super.key, required this.nav, required this.onSelect});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  static const _cols = 6;
  final _scrollCtrl = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    widget.nav.addListener(_onNavChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(watchlistProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    widget.nav.removeListener(_onNavChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    final row = widget.nav.contentRow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final ctx = _rowKeys[row]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchlistProvider);

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

  Widget _buildContent(List<SeriesResult> items) {
    final rows = <List<SeriesResult>>[];
    for (var i = 0; i < items.length; i += _cols) {
      rows.add(items.sublist(i, (i + _cols).clamp(0, items.length)));
    }

    // Build series_url → progress fraction from continue-watching provider.
    final continueState = ref.watch(continueWatchingProvider);
    final progressMap = <String, double>{};
    for (final p in continueState.items) {
      final url = p.seriesUrl ?? '';
      if (url.isNotEmpty && p.durationSeconds > 0) {
        progressMap[url] =
            (p.positionSeconds / p.durationSeconds).clamp(0.0, 1.0);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Always register at least 1 row so left-arrow can reach the sidebar.
      final rowLengths = rows.isEmpty ? [1] : rows.map((r) => r.length).toList();
      widget.nav.registerNav(rowLengths, (row, col) {
        if (rows.isEmpty) return;
        if (row < rows.length && col < rows[row].length) {
          widget.onSelect(rows[row][col]);
        }
      });
    });

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // ── Header ──────────────────────────────────────────────────────────
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
                'Meine Liste',
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

        const SizedBox(height: 32),

        // ── Empty state ──────────────────────────────────────────────────────
        if (items.isEmpty)
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
                    'Noch keine Serien gespeichert',
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
          // ── Poster grid ────────────────────────────────────────────────────
          ...List.generate(rows.length, (ri) {
            return Padding(
              key: _rowKeys.putIfAbsent(ri, GlobalKey.new),
              padding: const EdgeInsets.fromLTRB(44, 0, 44, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(
                    rows[ri].length,
                    (ci) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: ci < rows[ri].length - 1 ? 14 : 0),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ListenableBuilder(
                            listenable: widget.nav,
                            builder: (_, _) => RsPosterCard(
                              item: rows[ri][ci],
                              focused: widget.nav.isItemFocused(ri, ci),
                              inGrid: true,
                              progressFraction: progressMap[rows[ri][ci].url],
                              onTap: () => widget.onSelect(rows[ri][ci]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Fill remaining columns so partial rows align left
                  ...List.generate(
                    _cols - rows[ri].length,
                    (_) => const Expanded(child: SizedBox()),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
