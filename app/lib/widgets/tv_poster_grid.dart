import 'package:flutter/material.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../widgets/rs_poster.dart';

/// A TV D-pad navigable poster grid.
///
/// Renders [items] in [cols] equal-width columns. Automatically scrolls to
/// keep the focused row visible via [Scrollable.ensureVisible] on the nearest
/// scrollable ancestor.
///
/// Each grid row maps to nav row [navRowOffset + ri] in the
/// [AppNavController]. The parent is responsible for calling
/// [AppNavController.registerNav]; use [rowLengthsFor] to get the
/// right lengths list.
class TvPosterGrid extends StatefulWidget {
  final AppNavController nav;
  final List<SeriesResult> items;
  final int cols;

  /// Index of the first grid row in the AppNavController's row model.
  /// 0 when the grid is the only content; 1 or 2 when sort/genre rows
  /// come first.
  final int navRowOffset;

  final Map<String, double>? progressMap;
  final void Function(SeriesResult) onSelect;

  /// Optional custom renderer; falls back to [RsPosterCard].
  final Widget Function(SeriesResult item, bool focused, VoidCallback onTap)?
      itemBuilder;

  const TvPosterGrid({
    super.key,
    required this.nav,
    required this.items,
    required this.cols,
    this.navRowOffset = 0,
    this.progressMap,
    required this.onSelect,
    this.itemBuilder,
  });

  /// Returns the row-lengths list to pass to [AppNavController.registerNav]
  /// for the grid portion only (without rows above, like sort tabs).
  static List<int> rowLengthsFor(List<SeriesResult> items, int cols) {
    if (items.isEmpty) return [1];
    final out = <int>[];
    for (var i = 0; i < items.length; i += cols) {
      out.add(items.sublist(i, (i + cols).clamp(0, items.length)).length);
    }
    return out;
  }

  @override
  State<TvPosterGrid> createState() => _TvPosterGridState();
}

class _TvPosterGridState extends State<TvPosterGrid> {
  final _rowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    widget.nav.addListener(_onNavChanged);
  }

  @override
  void didUpdateWidget(TvPosterGrid old) {
    super.didUpdateWidget(old);
    if (old.nav != widget.nav) {
      old.nav.removeListener(_onNavChanged);
      widget.nav.addListener(_onNavChanged);
    }
    // Clear stale keys when items change significantly
    if (old.items.length != widget.items.length) _rowKeys.clear();
  }

  @override
  void dispose() {
    widget.nav.removeListener(_onNavChanged);
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    final row = widget.nav.contentRow;
    if (widget.nav.sidebarFocused) return;
    if (row < widget.navRowOffset) return;
    final gridRow = row - widget.navRowOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _rowKeys[gridRow]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<SeriesResult>>[];
    for (var i = 0; i < widget.items.length; i += widget.cols) {
      rows.add(
        widget.items.sublist(
          i,
          (i + widget.cols).clamp(0, widget.items.length),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (int ri = 0; ri < rows.length; ri++) ...[
          if (ri > 0) const SizedBox(height: 14),
          Padding(
            key: _rowKeys.putIfAbsent(ri, GlobalKey.new),
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: _PosterRow(
              nav: widget.nav,
              items: rows[ri],
              cols: widget.cols,
              navRow: widget.navRowOffset + ri,
              progressMap: widget.progressMap,
              onSelect: widget.onSelect,
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Single grid row ───────────────────────────────────────────────────────────

class _PosterRow extends StatelessWidget {
  final AppNavController nav;
  final List<SeriesResult> items;
  final int cols;
  final int navRow;
  final Map<String, double>? progressMap;
  final void Function(SeriesResult) onSelect;
  final Widget Function(SeriesResult, bool, VoidCallback)? itemBuilder;

  const _PosterRow({
    required this.nav,
    required this.items,
    required this.cols,
    required this.navRow,
    required this.onSelect,
    this.progressMap,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(cols, (ci) {
        final hasItem = ci < items.length;
        return [
          if (ci > 0) const SizedBox(width: 14),
          Expanded(
            child: hasItem
                ? AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ListenableBuilder(
                      listenable: nav,
                      builder: (_, _) {
                        final item = items[ci];
                        final focused = nav.isItemFocused(navRow, ci);
                        if (itemBuilder != null) {
                          return itemBuilder!(item, focused, () => onSelect(item));
                        }
                        return RsPosterCard(
                          item: item,
                          focused: focused,
                          inGrid: true,
                          progressFraction: progressMap?[item.url],
                          onTap: () => onSelect(item),
                        );
                      },
                    ),
                  )
                : const SizedBox(),
          ),
        ];
      }).expand((e) => e).toList(),
    );
  }
}
