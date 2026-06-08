import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import 'player_screen.dart';

// ── Nav entry types ───────────────────────────────────────────────────────────
sealed class _E {}

class _ERefresh extends _E {}

class _ETitle extends _E {
  final int idx;
  final LibraryTitle title;
  _ETitle(this.idx, this.title);
}

class _EEpisode extends _E {
  final int titleIdx;
  final LibraryTitle title;
  final int season;
  final LibraryEpisode ep;
  _EEpisode(
      {required this.titleIdx,
      required this.title,
      required this.season,
      required this.ep});
}

// ─────────────────────────────────────────────────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  const LibraryScreen({super.key, required this.nav});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _scrollCtrl = ScrollController();
  final _rowKeys = <int, GlobalKey>{};
  final _expanded = <int>{};

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = widget.nav.contentRow;
      final ctx = _rowKeys[row]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: 0.15);
      }
    });
  }

  List<_E> _buildEntries(List<LibraryTitle> titles) {
    final list = <_E>[_ERefresh()];
    for (int i = 0; i < titles.length; i++) {
      list.add(_ETitle(i, titles[i]));
      if (_expanded.contains(i)) {
        for (final s in titles[i].seasons.entries) {
          final sNum = int.tryParse(s.key) ?? 0;
          for (final ep in s.value.where((e) => e.isVideo)) {
            list.add(_EEpisode(
                titleIdx: i, title: titles[i], season: sNum, ep: ep));
          }
        }
      }
    }
    return list;
  }

  void _toggle(int idx) => setState(() {
        if (_expanded.contains(idx)) {
          _expanded.remove(idx);
        } else {
          _expanded.add(idx);
        }
      });

  void _playEpisode(BuildContext context, LibraryTitle title, int season,
      int episode) {
    final api = ref.read(apiServiceProvider);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        api: api,
        seriesTitle: title.folder,
        season: season,
        episode: episode,
        episodeTitle:
            'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
      ),
    ));
  }

  void _confirmDelete(BuildContext context, String folder,
      {int? season, int? episode}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Delete?', style: TextStyle(color: Rs.text)),
        content: Text(
          season == null
              ? 'Delete all files for "$folder"?'
              : episode == null
                  ? 'Delete Season $season of "$folder"?'
                  : 'Delete E${episode.toString().padLeft(2, '0')} of Season $season?',
          style: const TextStyle(color: Rs.muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(libraryProvider.notifier).delete(
                  folder: folder, season: season, episode: episode);
            },
            child: const Text('Löschen',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
          child: Row(
            children: [
              Text('Library', style: tt.displayMedium),
              const Spacer(),
              ListenableBuilder(
                listenable: widget.nav,
                builder: (_, _) {
                  final isFoc = widget.nav.isItemFocused(0, 0);
                  return GestureDetector(
                    onTap: () => ref.read(libraryProvider.notifier).load(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isFoc
                            ? Rs.accent.withValues(alpha: 0.18)
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isFoc ? Rs.accent : Colors.transparent,
                          width: 1.5,
                        ),
                        boxShadow: isFoc
                            ? [BoxShadow(color: Rs.glow(0.3), blurRadius: 12)]
                            : null,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              size: 18, color: Colors.white70),
                          SizedBox(width: 6),
                          Text('Refresh',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: state.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: Rs.accent)),
            error: (e, _) => Center(
              child: Text(e.toString(),
                  style: const TextStyle(color: Colors.white54)),
            ),
            data: (titles) {
              if (titles.isEmpty) {
                // Still register 1-item nav so Refresh is reachable
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.nav.registerNav([1], (_, _) {
                    ref.read(libraryProvider.notifier).load();
                  });
                });
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.video_library_outlined,
                          size: 64, color: Colors.white12),
                      const SizedBox(height: 16),
                      Text('No downloaded titles yet',
                          style:
                              tt.bodyLarge?.copyWith(color: Colors.white38)),
                    ],
                  ),
                );
              }

              final entries = _buildEntries(titles);

              // Nav column counts per row
              final colCounts = entries.map((e) => switch (e) {
                    _ERefresh() => 1,
                    _ETitle() => 2,
                    _EEpisode() => 2,
                  }).toList();

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                widget.nav.registerNav(colCounts, (row, col) {
                  if (row >= entries.length) return;
                  final entry = entries[row];
                  switch (entry) {
                    case _ERefresh():
                      ref.read(libraryProvider.notifier).load();
                    case _ETitle(:final idx, :final title):
                      if (col == 0) {
                        _toggle(idx);
                      } else {
                        _confirmDelete(context, title.folder);
                      }
                    case _EEpisode(:final title, :final season, :final ep):
                      if (col == 0) {
                        _playEpisode(context, title, season, ep.episode);
                      } else {
                        _confirmDelete(context, title.folder,
                            season: season, episode: ep.episode);
                      }
                  }
                });
              });

              return ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: List.generate(entries.length, (row) {
                  final entry = entries[row];
                  return switch (entry) {
                    _ERefresh() => const SizedBox.shrink(),
                    _ETitle(:final idx, :final title) =>
                      _buildTitleRow(context, row, idx, title, tt),
                    _EEpisode(:final title, :final season, :final ep) =>
                      _buildEpisodeRow(context, row, title, season, ep, tt),
                  };
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTitleRow(BuildContext context, int navRow, int idx,
      LibraryTitle title, TextTheme tt) {
    final isExpanded = _expanded.contains(idx);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenableBuilder(
          listenable: widget.nav,
          builder: (_, _) {
            final focExpand = widget.nav.isItemFocused(navRow, 0);
            final focDelete = widget.nav.isItemFocused(navRow, 1);
            return Container(
              key: _rowKeys.putIfAbsent(navRow, GlobalKey.new),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: (focExpand || focDelete)
                    ? Rs.accent.withValues(alpha: 0.06)
                    : Colors.transparent,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    // Expand / collapse button
                    GestureDetector(
                      onTap: () => _toggle(idx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: focExpand ? Rs.accent : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: focExpand
                              ? [
                                  BoxShadow(
                                      color: Rs.glow(0.25), blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: Icon(
                          isExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: focExpand ? Rs.accent : Colors.white38,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child:
                            Text(title.displayName, style: tt.titleMedium)),
                    Text(
                      '${title.totalEpisodes} ep  ${title.sizeFormatted}',
                      style: tt.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    // Delete button
                    GestureDetector(
                      onTap: () =>
                          _confirmDelete(context, title.folder),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: focDelete ? Colors.red : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: focDelete
                              ? [
                                  BoxShadow(
                                      color:
                                          Colors.red.withValues(alpha: 0.2),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color:
                              focDelete ? Colors.redAccent : Colors.white38,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const Divider(color: Color(0xFF222222), height: 1),
      ],
    );
  }

  Widget _buildEpisodeRow(BuildContext context, int navRow, LibraryTitle title,
      int season, LibraryEpisode ep, TextTheme tt) {
    return ListenableBuilder(
      listenable: widget.nav,
      builder: (_, _) {
        final focPlay = widget.nav.isItemFocused(navRow, 0);
        final focDel = widget.nav.isItemFocused(navRow, 1);
        return AnimatedContainer(
          key: _rowKeys.putIfAbsent(navRow, GlobalKey.new),
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(left: 40),
          padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: (focPlay || focDel)
                ? Rs.accent.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Text(
                'E${ep.episode.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    color: Rs.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(ep.file,
                      style: tt.bodyMedium,
                      overflow: TextOverflow.ellipsis)),
              Text(
                _fmtSize(ep.size),
                style: tt.bodyMedium?.copyWith(fontSize: 12),
              ),
              const SizedBox(width: 12),
              // Play button
              GestureDetector(
                onTap: () =>
                    _playEpisode(context, title, season, ep.episode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: focPlay
                        ? Rs.accent.withValues(alpha: 0.3)
                        : Rs.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: focPlay ? Rs.accent : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: focPlay
                        ? [BoxShadow(color: Rs.glow(0.3), blurRadius: 8)]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: focPlay ? Rs.text : Rs.accentLight,
                          size: 16),
                      const SizedBox(width: 4),
                      Text('Play',
                          style: TextStyle(
                              color: focPlay ? Rs.text : Rs.accentLight,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              GestureDetector(
                onTap: () => _confirmDelete(context, title.folder,
                    season: season, episode: ep.episode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: focDel ? Colors.red : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: focDel
                        ? [
                            BoxShadow(
                                color: Colors.red.withValues(alpha: 0.2),
                                blurRadius: 6)
                          ]
                        : null,
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      color: focDel ? Colors.redAccent : Colors.white38,
                      size: 18),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
