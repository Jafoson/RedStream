import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'player_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryProvider);
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
          child: Row(
            children: [
              Text('Library', style: tt.displayMedium),
              const Spacer(),
              TvFocusable(
                onActivate: () => ref.read(libraryProvider.notifier).load(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 6),
                      Text('Refresh', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(e.toString(), style: const TextStyle(color: Colors.white54)),
            ),
            data: (titles) => titles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.video_library_outlined, size: 64, color: Colors.white12),
                        const SizedBox(height: 16),
                        Text('No downloaded titles yet', style: tt.bodyLarge?.copyWith(color: Colors.white38)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    itemCount: titles.length,
                    separatorBuilder: (_, _) => const Divider(color: Color(0xFF222222), height: 1),
                    itemBuilder: (ctx, i) => _TitleTile(title: titles[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TitleTile extends ConsumerStatefulWidget {
  final LibraryTitle title;
  const _TitleTile({required this.title});

  @override
  ConsumerState<_TitleTile> createState() => _TitleTileState();
}

class _TitleTileState extends ConsumerState<_TitleTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final t = widget.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Title row ───────────────────────────────────────────────────
        TvFocusable(
          onActivate: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.white38,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t.displayName, style: tt.titleMedium)),
                Text(
                  '${t.totalEpisodes} ep  ${t.sizeFormatted}',
                  style: tt.bodyMedium,
                ),
                const SizedBox(width: 16),
                TvFocusable(
                  onActivate: () => _confirmDelete(context, t.folder),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Season / episode list ────────────────────────────────────────
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: t.seasons.entries.map((entry) {
                final sNum = int.tryParse(entry.key) ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Season $sNum',
                        style: tt.bodyMedium?.copyWith(color: cs.primary),
                      ),
                    ),
                    ...entry.value.where((e) => e.isVideo).map((ep) {
                      return TvFocusable(
                        onActivate: () => _playEpisode(context, sNum, ep.episode),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Row(
                            children: [
                              Text(
                                'E${ep.episode.toString().padLeft(2, '0')}',
                                style: tt.bodyMedium?.copyWith(color: cs.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(ep.file, style: tt.bodyMedium, overflow: TextOverflow.ellipsis)),
                              Text(
                                _fmtSize(ep.size),
                                style: tt.bodyMedium?.copyWith(fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              TvFocusable(
                                onActivate: () => _playEpisode(context, sNum, ep.episode),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.play_arrow_rounded, color: cs.primary, size: 16),
                                      const SizedBox(width: 4),
                                      Text('Play', style: TextStyle(color: cs.primary, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TvFocusable(
                                onActivate: () => _confirmDelete(context, t.folder, season: sNum, episode: ep.episode),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  void _playEpisode(BuildContext context, int season, int episode) {
    final api = ref.read(apiServiceProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: api,
          seriesTitle: widget.title.folder,
          season: season,
          episode: episode,
          episodeTitle: 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String folder, {int? season, int? episode}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Delete?'),
        content: Text(
          season == null
              ? 'Delete all files for "$folder"?'
              : episode == null
                  ? 'Delete Season $season of "$folder"?'
                  : 'Delete E${episode.toString().padLeft(2, '0')} of Season $season?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TvFocusable(
            autofocus: true,
            onActivate: () {
              Navigator.pop(ctx);
              ref.read(libraryProvider.notifier).delete(
                    folder: folder,
                    season: season,
                    episode: episode,
                  );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(6)),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
