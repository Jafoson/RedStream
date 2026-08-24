import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';
import '../widgets/tv_keyboard_dialog.dart';
import '../widgets/tv_poster_grid.dart';

// Nav rows (when TV keyboard is closed):
//   0 = search bar, 1 = category tabs, 2+ = result grid rows.
const _kbBase = 2;

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

class SearchScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;

  const SearchScreen({super.key, required this.nav, required this.onSelect});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  int _cols = 5;
  static const _cats = ['Alle', 'Serien', 'Anime', 'Filme'];
  static const _catSites = {
    'Alle': 'both',
    'Serien': 'sto',
    'Anime': 'aniworld',
    'Filme': 'megakino',
  };
  String _cat = 'Alle';
  String _query = '';

  // TV keyboard (Android TV only)
  bool _keyboardOpen = false;
  final _keyboardKey = GlobalKey<TvKeyboardInlineState>();

  // Desktop text field
  final _desktopCtrl = TextEditingController();
  final _desktopFocusNode = FocusNode();

  // Track sidebar focus transitions to auto-open keyboard / focus field when
  // the user navigates RIGHT from the sidebar into the search content area.
  bool _prevSidebarFocused = true;

  final _resultsScrollCtrl = ScrollController();
  final _resultRowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _prevSidebarFocused = widget.nav.sidebarFocused;
    widget.nav.addListener(_onNavChanged);

    if (_isDesktop) {
      _desktopFocusNode.addListener(_onDesktopFocusChanged);
      // Auto-focus the text field when navigating to the search screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.nav.sidebarFocused) {
          _desktopFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.nav.textInputActive = false;
    widget.nav.textInputFull = false;
    widget.nav.removeListener(_onNavChanged);
    _desktopFocusNode.removeListener(_onDesktopFocusChanged);
    _desktopFocusNode.dispose();
    _desktopCtrl.dispose();
    _resultsScrollCtrl.dispose();
    super.dispose();
  }

  // ── Desktop focus ─────────────────────────────────────────────────────────

  void _onDesktopFocusChanged() {
    if (_desktopFocusNode.hasFocus) {
      // textInputFull = false so UP/DOWN still exit text mode and navigate
      // results via D-pad (useful when a keyboard has arrow keys).
      widget.nav.textInputActive = true;
      widget.nav.textInputFull = false;
    } else {
      widget.nav.textInputActive = false;
      widget.nav.textInputFull = false;
    }
  }

  // ── TV keyboard mode ─────────────────────────────────────────────────────

  void _enterKeyboardMode() {
    if (_isDesktop) {
      _desktopFocusNode.requestFocus();
      return;
    }
    setState(() => _keyboardOpen = true);
    widget.nav.textInputActive = true;
    widget.nav.textInputFull = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardKey.currentState?.requestFocus();
    });
  }

  void _exitKeyboardMode() {
    if (_isDesktop) {
      _desktopFocusNode.unfocus();
      return;
    }
    setState(() => _keyboardOpen = false);
    widget.nav.textInputActive = false;
    widget.nav.textInputFull = false;
  }

  void _onQueryChanged(String text) {
    setState(() => _query = text);
    ref.read(searchProvider.notifier).search(text);
  }

  void _clearSearch() {
    setState(() => _query = '');
    _desktopCtrl.clear();
    ref.read(searchProvider.notifier).clear();
    if (_isDesktop) {
      _desktopFocusNode.requestFocus();
    } else {
      _enterKeyboardMode();
    }
  }

  void _selectCat(String cat) {
    setState(() => _cat = cat);
    ref.read(searchProvider.notifier).setSite(_catSites[cat]!);
  }

  // ── Nav listener ─────────────────────────────────────────────────────────

  void _onNavChanged() {
    if (!mounted) return;

    final sidebarFocused = widget.nav.sidebarFocused;
    final sidebarJustLeft = _prevSidebarFocused && !sidebarFocused;
    _prevSidebarFocused = sidebarFocused;

    if (sidebarJustLeft && widget.nav.screen == NavScreen.search) {
      if (_isDesktop) {
        _desktopFocusNode.requestFocus();
      } else if (!_keyboardOpen) {
        _enterKeyboardMode();
      }
      return;
    }

    // Scroll results when navigating (TV keyboard closed only)
    if (!_isDesktop && _keyboardOpen) return;
    final row = widget.nav.contentRow;
    if (row < _kbBase) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resultsScrollCtrl.hasClients) return;
      final ctx = _resultRowKeys[row]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: 0.1);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
    final search = ref.watch(searchProvider);
    final results = search.results;

    final resRows = <List<SeriesResult>>[];
    for (var i = 0; i < results.length; i += _cols) {
      resRows.add(results.sublist(i, (i + _cols).clamp(0, results.length)));
    }

    // Register nav for when TV keyboard is closed (always on desktop)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav(
        [1, _cats.length, ...resRows.map((r) => r.length)],
        (row, col) {
          if (row == 0) {
            _enterKeyboardMode();
          } else if (row == 1) {
            _selectCat(_cats[col]);
          } else {
            final ri = row - _kbBase;
            if (ri < resRows.length && col < resRows[ri].length) {
              widget.onSelect(resRows[ri][col]);
            }
          }
        },
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Search bar ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 22, 44, 0),
          child: _isDesktop
              ? _buildDesktopSearchBar(search.loading)
              : _buildTvSearchBar(),
        ),

        // ── TV keyboard (Android TV only) ─────────────────────────────────────
        if (!_isDesktop && _keyboardOpen) ...[
          const SizedBox(height: 8),
          TvKeyboardInline(
            key: _keyboardKey,
            initialText: _query,
            onChanged: _onQueryChanged,
            onExitKeyboard: _exitKeyboardMode,
          ),
        ],

        // ── Category tabs ─────────────────────────────────────────────────────
        // Always shown on desktop; on TV only when keyboard is closed.
        if (_isDesktop || !_keyboardOpen) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: ListenableBuilder(
              listenable: widget.nav,
              builder: (_, _) => Row(
                children: List.generate(_cats.length, (i) {
                  final isFoc = widget.nav.isItemFocused(1, i);
                  final isOn = _cats[i] == _cat;
                  return Padding(
                    padding:
                        EdgeInsets.only(right: i < _cats.length - 1 ? 10 : 0),
                    child: GestureDetector(
                      onTap: () => _selectCat(_cats[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
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
                                    blurRadius: 14,
                                  )
                                ]
                              : null,
                        ),
                        child: Text(
                          _cats[i],
                          style: TextStyle(
                            fontSize: 12,
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
        ],

        const SizedBox(height: 10),

        // ── Results ────────────────────────────────────────────────────────────
        Expanded(
          child: ListView(
            controller: _resultsScrollCtrl,
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 10),
                child: Row(
                  children: [
                    Text(
                      _query.isNotEmpty ? 'Ergebnisse' : 'Beliebte Titel',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Rs.text,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (search.loading)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Rs.accent, strokeWidth: 2))
                    else if (results.isNotEmpty)
                      Text('${results.length} Titel',
                          style: const TextStyle(
                              fontSize: 13, color: Rs.muted)),
                  ],
                ),
              ),

              // Empty states
              if (!search.loading && results.isEmpty && _query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.search_off_rounded,
                            color: Rs.muted2, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          'Keine Treffer für „$_query"',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Rs.muted),
                        ),
                      ],
                    ),
                  ),
                ),

              if (!search.loading && results.isEmpty && _query.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.keyboard_rounded,
                            color: Rs.muted2.withValues(alpha: 0.5), size: 44),
                        const SizedBox(height: 12),
                        Text(
                          _isDesktop
                              ? 'Titel über die Tastatur eingeben'
                              : 'Tippe mit der Tastatur einen Titel ein',
                          style: const TextStyle(
                              fontSize: 13, color: Rs.muted2),
                        ),
                      ],
                    ),
                  ),
                ),

              // Result grid
              ...List.generate(resRows.length, (ri) {
                final navRow = _kbBase + ri;
                return Padding(
                  key: _resultRowKeys.putIfAbsent(navRow, GlobalKey.new),
                  padding: const EdgeInsets.fromLTRB(44, 0, 44, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...List.generate(
                        resRows[ri].length,
                        (ci) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: ci < resRows[ri].length - 1 ? 14 : 0),
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ListenableBuilder(
                                listenable: widget.nav,
                                builder: (_, _) => RsPosterCard(
                                  item: resRows[ri][ci],
                                  focused: (!_isDesktop && !_keyboardOpen &&
                                          widget.nav.isItemFocused(navRow, ci)) ||
                                      (_isDesktop &&
                                          widget.nav
                                              .isItemFocused(navRow, ci)),
                                  inGrid: true,
                                  onTap: () =>
                                      widget.onSelect(resRows[ri][ci]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      ...List.generate(
                        _cols - resRows[ri].length,
                        (_) => const Expanded(child: SizedBox()),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── Search bar variants ───────────────────────────────────────────────────

  Widget _buildDesktopSearchBar(bool loading) {
    return AnimatedBuilder(
      animation: _desktopFocusNode,
      builder: (_, _) {
        final focused = _desktopFocusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: Rs.panel2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? Rs.accent : Rs.line,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Rs.accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded,
                  color: focused ? Rs.accent : Rs.muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _desktopCtrl,
                  focusNode: _desktopFocusNode,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Rs.text,
                  ),
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Titel suchen …',
                    hintStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Rs.muted2,
                    ),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Rs.accent, strokeWidth: 2),
                  ),
                )
              else if (_query.isNotEmpty)
                GestureDetector(
                  onTap: _clearSearch,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.close_rounded,
                        color: Rs.muted, size: 18),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTvSearchBar() {
    return ListenableBuilder(
      listenable: widget.nav,
      builder: (_, _) {
        final navFocused =
            !_keyboardOpen && widget.nav.isItemFocused(0, 0);
        final highlighted = _keyboardOpen || navFocused;
        return GestureDetector(
          onTap: _enterKeyboardMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Rs.panel2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlighted ? Rs.accent : Rs.line,
                width: highlighted ? 2 : 1,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: Rs.accent.withValues(alpha: 0.22),
                        blurRadius: 14,
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    color: highlighted ? Rs.accent : Rs.muted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _query.isEmpty ? 'Titel suchen …' : _query,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _query.isEmpty ? Rs.muted2 : Rs.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.close_rounded,
                          color: Rs.muted, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
