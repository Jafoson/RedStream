import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_poster.dart';
import '../widgets/rs_rail.dart';
import '../widgets/rs_sidebar.dart';
import 'detail_screen.dart';
import 'download_play_screen.dart';
import 'grid_screen.dart';
import 'library_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'watchlist_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App shell — sidebar + content area + toast overlay
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final AppNavController _nav;

  @override
  void initState() {
    super.initState();
    _nav = ref.read(appNavProvider);
    _nav.attach();
    _nav.setProfileSwitchCallback(_openProfilePicker);
  }

  @override
  void dispose() {
    _nav.detach();
    super.dispose();
  }

  Future<void> _openProfilePicker() async {
    _nav.detach();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen(canPop: true)),
    );
    if (mounted) {
      _nav.attach();
      _nav.switchScreen(NavScreen.home);
    }
  }

  void _openDetail(SeriesResult item) async {
    _nav.detach();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(seriesUrl: item.url, title: item.title),
      ),
    );
    if (mounted) {
      _nav.attach();
      ref.read(continueWatchingProvider.notifier).refresh();
    }
  }

  Future<void> _openFromProgress(WatchProgress p) async {
    _nav.detach();
    // Frontier is completed → the next episode to watch; open the series detail
    // page so the correct "Nächste Folge" button is shown with the right URL.
    if (p.completed) {
      _openDetail(SeriesResult(
        title: p.seriesTitle ?? '',
        url: p.seriesUrl ?? p.episodeUrl,
        posterUrl: p.posterUrl,
      ));
      return;
    }
    final api = ref.read(apiServiceProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DownloadPlayScreen(
          api: api,
          episodeUrl: p.episodeUrl,
          seriesUrl: p.seriesUrl ?? '',
          seriesTitle: p.seriesTitle ?? '',
          season: p.season,
          episodeNumber: p.episodeNumber,
          episodeTitle: p.episodeTitle ?? '',
          availableLanguages: const [],
        ),
      ),
    );
    if (mounted) {
      _nav.attach();
      ref.read(continueWatchingProvider.notifier).refresh();
    }
  }

  Widget _buildContent() {
    return ListenableBuilder(
      listenable: _nav,
      builder: (context, _) {
        switch (_nav.screen) {
          case NavScreen.serien:
            return GridScreen(key: const ValueKey('serien'), nav: _nav, kind: GridKind.series, onSelect: _openDetail);
          case NavScreen.anime:
            return GridScreen(key: const ValueKey('anime'), nav: _nav, kind: GridKind.anime, onSelect: _openDetail);
          case NavScreen.search:
            return SearchScreen(nav: _nav, onSelect: _openDetail);
          case NavScreen.queue:
            return QueueScreen(nav: _nav);
          case NavScreen.library:
            return LibraryScreen(nav: _nav);
          case NavScreen.watchlist:
            return WatchlistScreen(nav: _nav, onSelect: _openDetail);
          case NavScreen.settings:
            return SettingsScreen(nav: _nav);
          case NavScreen.home:
            return _HomeContent(
              nav: _nav,
              onSelect: _openDetail,
              onContinue: _openFromProgress,
            );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rs.bg,
      body: Stack(
        children: [
          Row(
            children: [
              RsSidebar(nav: _nav),
              Expanded(child: _buildContent()),
            ],
          ),
          // Toast overlay
          ListenableBuilder(
            listenable: _nav,
            builder: (_, _) {
              final msg = _nav.toast;
              if (msg == null) { return const SizedBox.shrink(); }
              return Positioned(
                bottom: 64,
                left: 0,
                right: 0,
                child: Center(
                  child: _Toast(message: msg),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String message;
  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      decoration: BoxDecoration(
        color: Rs.accent,
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 44)],
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home content — greeting + rails
// ─────────────────────────────────────────────────────────────────────────────

class _HomeContent extends ConsumerStatefulWidget {
  final AppNavController nav;
  final void Function(SeriesResult) onSelect;
  final void Function(WatchProgress) onContinue;
  const _HomeContent({
    required this.nav,
    required this.onSelect,
    required this.onContinue,
  });

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  final _scrollCtrl = ScrollController();
  // Keyed by nav-row index so ensureVisible works regardless of which rails
  // are currently visible (continue/watchlist/browse can each be absent).
  final _rowKeys = <int, GlobalKey>{};
  int _lastScrollRow = -1;

  @override
  void initState() {
    super.initState();
    widget.nav.addListener(_onNavChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(continueWatchingProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    widget.nav.removeListener(_onNavChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) { return; }
    final row = widget.nav.contentRow;
    if (row == _lastScrollRow) { return; } // skip if row didn't change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) { return; }
      _scrollToRow(row);
    });
  }

  void _scrollToRow(int row) {
    if (!_scrollCtrl.hasClients) { return; }
    _lastScrollRow = row;
    // Row 0 → always scroll to the very top so the header is fully visible.
    if (row == 0) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    final ctx = _rowKeys[row]?.currentContext;
    if (ctx == null) { return; }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browseProvider);
    final continueState = ref.watch(continueWatchingProvider);
    final watchlistState = ref.watch(watchlistProvider);

    final continueItems = continueState.items;
    final hasContinue = continueItems.isNotEmpty;
    final watchlistItems = watchlistState.valueOrNull ?? [];
    final hasWatchlist = watchlistItems.isNotEmpty;

    if (state.loading && state.newAnimes.isEmpty && state.newSeries.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Rs.accent, strokeWidth: 2),
      );
    }

    if (state.error != null && state.newAnimes.isEmpty) {
      return _ErrorView(
        error: state.error!,
        onRetry: () => ref.read(browseProvider.notifier).load(),
      );
    }

    final browseRows = [
      state.newAnimes,
      state.popularAnimes,
      state.newSeries,
      state.popularSeries,
    ];

    // Nav row layout:
    //   row 0              : continue watching (if present)
    //   row continueOff    : meine liste (if present)
    //   row browseOff + i  : browse rails
    final continueOff = hasContinue ? 1 : 0;
    final watchlistNavRow = continueOff;
    final browseOff = continueOff + (hasWatchlist ? 1 : 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) { return; }
      final rowLengths = [
        if (hasContinue) continueItems.length,
        if (hasWatchlist) watchlistItems.length,
        ...browseRows.map((r) => r.isEmpty ? 1 : r.length),
      ];
      widget.nav.registerNav(rowLengths, (row, col) {
        var r = row;
        if (hasContinue) {
          if (r == 0) { widget.onContinue(continueItems[col]); return; }
          r--;
        }
        if (hasWatchlist) {
          if (r == 0) { widget.onSelect(watchlistItems[col]); return; }
          r--;
        }
        final br = browseRows[r];
        if (br.isNotEmpty) { widget.onSelect(br[col]); }
      });
      _scrollToRow(widget.nav.contentRow);
    });

    final profileName = ref.watch(activeProfileNameProvider).valueOrNull;

    final now = DateTime.now();
    final h = now.hour;
    final greet = h < 5
        ? 'Gute Nacht'
        : h < 11
            ? 'Guten Morgen'
            : h < 17
                ? 'Hallo'
                : h < 22
                    ? 'Guten Abend'
                    : 'Gute Nacht';

    final clock = TimeOfDay.fromDateTime(now).format(context);
    final day =
        '${_weekday(now.weekday)}, ${now.day}. ${_month(now.month)} ${now.year}';

    return SingleChildScrollView(
      controller: _scrollCtrl,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting header
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 40, 44, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: Rs.text,
                            letterSpacing: -1.2,
                          ),
                          children: [
                            TextSpan(text: '$greet, '),
                            TextSpan(
                              text: profileName ?? 'Willkommen',
                              style: const TextStyle(color: Rs.accent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Was möchtest du heute sehen?',
                        style: TextStyle(
                          fontSize: 17,
                          color: Rs.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      clock,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Rs.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      day,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Rs.muted2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (hasContinue)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(0, GlobalKey.new),
              child: _ContinueRail(
                items: continueItems,
                nav: widget.nav,
                rowIndex: 0,
                onSelect: widget.onContinue,
              ),
            ),
          if (hasWatchlist)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(watchlistNavRow, GlobalKey.new),
              child: RsRail(
                title: 'Watchlist',
                linkLabel: 'Alle',
                rowIndex: watchlistNavRow,
                items: watchlistItems,
                nav: widget.nav,
                onSelect: widget.onSelect,
              ),
            ),
          if (state.newAnimes.isNotEmpty)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(browseOff + 0, GlobalKey.new),
              child: RsRail(
                title: 'Neue Anime',
                linkLabel: 'Alle',
                rowIndex: browseOff + 0,
                items: state.newAnimes,
                nav: widget.nav,
                onSelect: widget.onSelect,
              ),
            ),
          if (state.popularAnimes.isNotEmpty)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(browseOff + 1, GlobalKey.new),
              child: RsRail(
                title: 'Beliebte Anime',
                rowIndex: browseOff + 1,
                items: state.popularAnimes,
                nav: widget.nav,
                onSelect: widget.onSelect,
              ),
            ),
          if (state.newSeries.isNotEmpty)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(browseOff + 2, GlobalKey.new),
              child: RsRail(
                title: 'Neue Serien',
                linkLabel: 'Alle',
                rowIndex: browseOff + 2,
                items: state.newSeries,
                nav: widget.nav,
                onSelect: widget.onSelect,
              ),
            ),
          if (state.popularSeries.isNotEmpty)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(browseOff + 3, GlobalKey.new),
              child: RsRail(
                title: 'Beliebte Serien',
                rowIndex: browseOff + 3,
                items: state.popularSeries,
                nav: widget.nav,
                onSelect: widget.onSelect,
              ),
            ),

          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Continue Watching rail
// ─────────────────────────────────────────────────────────────────────────────

class _ContinueRail extends StatefulWidget {
  final List<WatchProgress> items;
  final AppNavController nav;
  final int rowIndex;
  final void Function(WatchProgress) onSelect;

  const _ContinueRail({
    required this.items,
    required this.nav,
    required this.rowIndex,
    required this.onSelect,
  });

  @override
  State<_ContinueRail> createState() => _ContinueRailState();
}

class _ContinueRailState extends State<_ContinueRail> {
  final _scrollCtrl = ScrollController();

  static const _hPad = 44.0;
  static const _gap = 20.0;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCol(int col) {
    if (!_scrollCtrl.hasClients) { return; }
    final step = Rs.cwW + _gap;
    final target =
        (col * step - _hPad).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(44, 24, 44, 12),
          child: Text(
            'Weiterschauen',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Rs.text,
              letterSpacing: -0.4,
            ),
          ),
        ),
        SizedBox(
          height: Rs.cwH + 36,
          child: ListenableBuilder(
            listenable: widget.nav,
            builder: (_, _) {
              // No sidebarFocused check — keeps orange border when sidebar activates.
              final focused = widget.nav.contentRow == widget.rowIndex;
              final focusedCol = focused ? widget.nav.contentCol : -1;
              if (focused && !widget.nav.sidebarFocused) {
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToCol(focusedCol));
              }
              return ListView.builder(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(_hPad, 18, _hPad, 18),
                itemCount: widget.items.length,
                itemBuilder: (context, i) {
                  final p = widget.items[i];
                  final isFocused = focusedCol == i;
                  final fraction = p.durationSeconds > 0
                      ? (p.positionSeconds / p.durationSeconds)
                          .clamp(0.0, 1.0)
                      : 0.0;
                  final item = SeriesResult(
                    title: p.seriesTitle ?? p.episodeTitle ?? 'Unbekannt',
                    url: p.seriesUrl ?? p.episodeUrl,
                    posterUrl: p.posterUrl,
                  );
                  return Padding(
                    padding: EdgeInsets.only(
                        right: i < widget.items.length - 1 ? _gap : 0),
                    child: RsContinueCard(
                      item: item,
                      focused: isFocused,
                      epLabel: p.completed
                          ? 'S${p.season} E${p.episodeNumber + 1}'
                          : 'S${p.season} E${p.episodeNumber}',
                      progressFraction: p.completed ? 0 : fraction,
                      thumbnailUrl: p.previewUrl.isNotEmpty ? p.previewUrl : null,
                      onTap: () => widget.onSelect(p),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 64, color: Rs.muted2),
          const SizedBox(height: 20),
          Text(error,
              style: const TextStyle(color: Rs.muted, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: Rs.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Erneut versuchen',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── date helpers ─────────────────────────────────────────────────────────────

String _weekday(int d) => const [
      '', 'Montag', 'Dienstag', 'Mittwoch',
      'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'
    ][d];

String _month(int m) => const [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ][m];
