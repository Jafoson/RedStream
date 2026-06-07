import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';

// QWERTZ keyboard rows (German layout matching the design).
const _kbRows = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['Q', 'W', 'E', 'R', 'T', 'Z', 'U', 'I', 'O', 'P'],
  ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
  ['Y', 'X', 'C', 'V', 'B', 'N', 'M'],
];

const _kbSpecial = ['LEERZEICHEN', 'LÖSCHEN', 'LEEREN'];

// Row 6 onwards = result rows.
const _kbBase = 6;

/// Search screen with on-screen QWERTZ keyboard and live results grid.
class SearchScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;

  const SearchScreen({super.key, required this.nav, required this.onSelect});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _cols = 5;
  static const _cats = ['Alle', 'Serien', 'Anime'];
  String _cat = 'Alle';

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final query = search.query;
    final results = search.results;

    final resRows = <List<SeriesResult>>[];
    for (var i = 0; i < results.length; i += _cols) {
      resRows.add(results.sublist(i, (i + _cols).clamp(0, results.length)));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.nav.registerNav(
        [
          _cats.length,
          _kbRows[0].length,
          _kbRows[1].length,
          _kbRows[2].length,
          _kbRows[3].length,
          _kbSpecial.length,
          ...resRows.map((r) => r.length),
        ],
        (row, col) {
          if (row == 0) {
            setState(() => _cat = _cats[col]);
          } else if (row >= 1 && row <= 4) {
            _type(_kbRows[row - 1][col]);
          } else if (row == 5) {
            if (col == 0) { _type(' '); }
            else if (col == 1) { _backspace(); }
            else { _clear(); }
          } else if (row >= _kbBase) {
            final ri = row - _kbBase;
            if (ri < resRows.length && col < resRows[ri].length) {
              widget.onSelect(resRows[ri][col]);
            }
          }
        },
      );
    });

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Category tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 32, 44, 20),
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_cats.length, (i) {
                final isFoc = widget.nav.isItemFocused(0, i);
                final isOn = _cats[i] == _cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 11),
                  child: GestureDetector(
                    onTap: () => setState(() => _cat = _cats[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isOn ? Colors.white : Rs.panel2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isFoc ? Rs.accent : Rs.line,
                          width: isFoc ? 2 : 1,
                        ),
                        boxShadow: isFoc
                            ? [
                                BoxShadow(
                                  color: Rs.accent.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        _cats[i],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isOn ? const Color(0xFF111111) : Rs.muted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        // Query display bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Rs.panel2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Rs.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Rs.accent, size: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: query.isEmpty
                      ? const Text(
                          'Titel oder Genre suchen',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: Rs.muted2),
                        )
                      : Text(
                          query,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Rs.text),
                        ),
                ),
                _Cursor(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),

        // On-screen keyboard
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) => Column(
              children: [
                ...List.generate(_kbRows.length, (ri) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: List.generate(_kbRows[ri].length, (ci) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: ci < _kbRows[ri].length - 1 ? 10 : 0),
                          child: _Key(
                            label: _kbRows[ri][ci],
                            focused: widget.nav.isItemFocused(ri + 1, ci),
                            onTap: () => _type(_kbRows[ri][ci]),
                          ),
                        ),
                      );
                    }),
                  ),
                )),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Key(
                          label: 'LEERZEICHEN',
                          icon: Icons.space_bar_rounded,
                          focused: widget.nav.isItemFocused(5, 0),
                          wide: true,
                          onTap: () => _type(' '),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Key(
                          label: 'LÖSCHEN',
                          icon: Icons.backspace_rounded,
                          focused: widget.nav.isItemFocused(5, 1),
                          wide: true,
                          onTap: _backspace,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: _Key(
                        label: 'LEEREN',
                        focused: widget.nav.isItemFocused(5, 2),
                        wide: true,
                        onTap: _clear,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Results section header
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 0, 44, 12),
          child: Row(
            children: [
              Text(
                query.isNotEmpty ? 'Ergebnisse' : 'Beliebte Titel',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Rs.text,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              if (search.loading)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Rs.accent, strokeWidth: 2),
                )
              else
                Text('${results.length} Titel',
                    style: const TextStyle(fontSize: 15, color: Rs.muted)),
            ],
          ),
        ),

        // Empty state
        if (!search.loading && results.isEmpty && query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, color: Rs.muted2, size: 52),
                  const SizedBox(height: 14),
                  Text(
                    'Keine Treffer für „$query"',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: Rs.muted),
                  ),
                  const SizedBox(height: 6),
                  const Text('Versuch einen anderen Titel oder ein Genre.',
                      style: TextStyle(color: Rs.muted2)),
                ],
              ),
            ),
          ),

        // Result rows
        ...List.generate(resRows.length, (ri) => Padding(
          padding: const EdgeInsets.fromLTRB(44, 0, 44, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(resRows[ri].length, (ci) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: ci < resRows[ri].length - 1 ? 18 : 0),
                  child: ListenableBuilder(
                    listenable: widget.nav,
                    builder: (_, _) => RsPosterCard(
                      item: resRows[ri][ci],
                      focused: widget.nav.isItemFocused(_kbBase + ri, ci),
                      inGrid: true,
                      onTap: () => widget.onSelect(resRows[ri][ci]),
                    ),
                  ),
                ),
              );
            }),
          ),
        )),

        const SizedBox(height: 60),
      ],
    );
  }

  void _type(String ch) {
    final q = ref.read(searchProvider).query;
    ref.read(searchProvider.notifier).search(q + ch);
  }

  void _backspace() {
    final q = ref.read(searchProvider).query;
    if (q.isNotEmpty) {
      ref.read(searchProvider.notifier).search(q.substring(0, q.length - 1));
    }
  }

  void _clear() => ref.read(searchProvider.notifier).clear();
}

// ── Keyboard key ─────────────────────────────────────────────────────────────

class _Key extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool focused;
  final bool wide;
  final VoidCallback onTap;

  const _Key({
    required this.label,
    this.icon,
    required this.focused,
    this.wide = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 58,
        decoration: BoxDecoration(
          color: focused ? Rs.accent : Rs.panel2,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: focused ? Rs.accent : Rs.line),
          boxShadow: focused
              ? [BoxShadow(color: Rs.accent.withValues(alpha: 0.4), blurRadius: 16)]
              : null,
        ),
        child: Center(
          child: wide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon,
                          size: 17,
                          color: focused ? Colors.white : Rs.muted),
                      const SizedBox(width: 7),
                    ],
                    Text(label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: focused ? Colors.white : Rs.muted,
                        )),
                  ],
                )
              : Text(label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: focused ? Colors.white : const Color(0xFFE7E7E8),
                  )),
        ),
      ),
    );
  }
}

// ── Blinking cursor ───────────────────────────────────────────────────────────

class _Cursor extends StatefulWidget {
  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: _ctrl.value > 0.5 ? 0.0 : 1.0,
        child: Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            color: Rs.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
