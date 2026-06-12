import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../utils/tv_keyboard.dart';
import '../widgets/rs_poster.dart';

// Nav rows: 0 = search bar, 1 = category tabs, 2+ = result grid rows.
const _kbBase = 2;

class SearchScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;

  const SearchScreen({super.key, required this.nav, required this.onSelect});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _cols = 6;
  static const _cats = ['Alle', 'Serien', 'Anime'];
  static const _catSites = {'Alle': 'both', 'Serien': 'sto', 'Anime': 'aniworld'};
  String _cat = 'Alle';

  final _ctrl = TextEditingController();
  final _searchFocus = FocusNode(skipTraversal: true);
  final _resultsScrollCtrl = ScrollController();
  final _resultRowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
    _searchFocus.showKeyboardOnFocus();
    widget.nav.addListener(_onNavChanged);
  }

  @override
  void dispose() {
    // Ensure nav is re-enabled when leaving search screen
    widget.nav.textInputActive = false;
    _searchFocus.removeListener(_onSearchFocusChange);
    widget.nav.removeListener(_onNavChanged);
    _ctrl.dispose();
    _searchFocus.dispose();
    _resultsScrollCtrl.dispose();
    super.dispose();
  }

  void _selectCat(String cat) {
    setState(() => _cat = cat);
    ref.read(searchProvider.notifier).setSite(_catSites[cat]!);
  }

  void _onSearchFocusChange() {
    widget.nav.textInputActive = _searchFocus.hasFocus;
  }

  void _onNavChanged() {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final results = search.results;

    final resRows = <List<SeriesResult>>[];
    for (var i = 0; i < results.length; i += _cols) {
      resRows.add(results.sublist(i, (i + _cols).clamp(0, results.length)));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav(
        [
          1,                                   // row 0: search bar
          _cats.length,                        // row 1: category tabs
          ...resRows.map((r) => r.length),     // rows 2+: result grid
        ],
        (row, col) {
          if (row == 0) {
            _searchFocus.requestFocus();       // open native keyboard
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

    return ListView(
      controller: _resultsScrollCtrl,
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // ── Search bar ───────────────────────────────────────────────────────
        // ── Search bar (nav row 0) ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 28, 44, 0),
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) {
              final navFocused = widget.nav.isItemFocused(0, 0);
              return GestureDetector(
                onTap: _searchFocus.requestFocus,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _searchFocus,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Rs.text),
                  cursorColor: Rs.accent,
                  cursorWidth: 2.5,
                  onChanged: (v) =>
                      ref.read(searchProvider.notifier).search(v),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchFocus.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Titel suchen … (Enter zum Tippen)',
                    hintStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Rs.muted2),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.search_rounded,
                          color: Rs.accent, size: 24),
                    ),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Rs.muted, size: 20),
                            onPressed: () {
                              _ctrl.clear();
                              ref.read(searchProvider.notifier).clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Rs.panel2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Rs.line),
                    ),
                    // Nav D-pad focus: orange glow border
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: navFocused ? Rs.accent : Rs.line,
                        width: navFocused ? 2 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: Rs.accent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // ── Category tabs ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) => Row(
              children: List.generate(_cats.length, (i) {
                final isFoc = widget.nav.isItemFocused(1, i);
                final isOn = _cats[i] == _cat;
                return Padding(
                  padding: EdgeInsets.only(
                      right: i < _cats.length - 1 ? 10 : 0),
                  child: GestureDetector(
                    onTap: () => _selectCat(_cats[i]),
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
                                  blurRadius: 14,
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        _cats[i],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              isOn ? const Color(0xFF111111) : Rs.muted,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Results header ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Row(
            children: [
              Text(
                _ctrl.text.isNotEmpty ? 'Ergebnisse' : 'Beliebte Titel',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Rs.text,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 12),
              if (search.loading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Rs.accent, strokeWidth: 2))
              else if (results.isNotEmpty)
                Text('${results.length} Titel',
                    style:
                        const TextStyle(fontSize: 15, color: Rs.muted)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Empty / idle states ──────────────────────────────────────────────
        if (!search.loading && results.isEmpty && _ctrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded,
                      color: Rs.muted2, size: 52),
                  const SizedBox(height: 14),
                  Text(
                    'Keine Treffer für „${_ctrl.text}"',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Rs.muted),
                  ),
                ],
              ),
            ),
          ),

        if (!search.loading && results.isEmpty && _ctrl.text.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.keyboard_rounded,
                      color: Rs.muted2.withValues(alpha: 0.5), size: 56),
                  const SizedBox(height: 14),
                  const Text('Tippe einen Titel ein',
                      style: TextStyle(fontSize: 16, color: Rs.muted2)),
                  const SizedBox(height: 6),
                  const Text('Drücke Enter um die Tastatur zu öffnen',
                      style: TextStyle(fontSize: 13, color: Rs.muted2)),
                ],
              ),
            ),
          ),

        // ── Result grid ──────────────────────────────────────────────────────
        ...List.generate(resRows.length, (ri) {
          final navRow = _kbBase + ri;
          return Padding(
            key: _resultRowKeys.putIfAbsent(navRow, GlobalKey.new),
            padding: const EdgeInsets.fromLTRB(44, 0, 44, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...List.generate(resRows[ri].length, (ci) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: ci < resRows[ri].length - 1 ? 14 : 0),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ListenableBuilder(
                        listenable: widget.nav,
                        builder: (_, _) => RsPosterCard(
                          item: resRows[ri][ci],
                          focused: widget.nav.isItemFocused(navRow, ci),
                          inGrid: true,
                          onTap: () => widget.onSelect(resRows[ri][ci]),
                        ),
                      ),
                    ),
                  ),
                )),
                ...List.generate(
                    _cols - resRows[ri].length,
                    (_) => const Expanded(child: SizedBox())),
              ],
            ),
          );
        }),
      ],
    );
  }
}
