import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(queueProvider);
    final notifier = ref.read(queueProvider.notifier);
    final tt = Theme.of(context).textTheme;

    final active = state.items.where((i) => !i.isDone && !i.isFailed).toList();
    final completed = state.items.where((i) => i.isDone || i.isFailed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            children: [
              Text('Download Queue', style: tt.displayMedium),
              const Spacer(),
              if (completed.isNotEmpty)
                TvFocusable(
                  onActivate: notifier.clearCompleted,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Clear completed', style: TextStyle(color: Colors.white70)),
                  ),
                ),
            ],
          ),
        ),

        // ── FFmpeg live progress ────────────────────────────────────────
        if (state.ffmpeg.active)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
            child: _FfmpegBanner(progress: state.ffmpeg),
          ),

        const SizedBox(height: 16),

        // ── Queue list ──────────────────────────────────────────────────
        Expanded(
          child: state.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_done_rounded, size: 64, color: Colors.white12),
                      const SizedBox(height: 16),
                      Text('Queue is empty', style: tt.bodyLarge?.copyWith(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  children: [
                    if (active.isNotEmpty) ...[
                      Text('Active', style: tt.titleMedium?.copyWith(color: Colors.white54)),
                      const SizedBox(height: 8),
                      ...active.map((item) => _QueueTile(item: item, notifier: notifier)),
                      const SizedBox(height: 24),
                    ],
                    if (completed.isNotEmpty) ...[
                      Text('Completed', style: tt.titleMedium?.copyWith(color: Colors.white54)),
                      const SizedBox(height: 8),
                      ...completed.map((item) => _QueueTile(item: item, notifier: notifier)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FfmpegBanner extends StatelessWidget {
  final FfmpegProgress progress;
  const _FfmpegBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Downloading — ${progress.percent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${progress.time}  ${progress.speed}  ${progress.bandwidth}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.percent / 100,
            backgroundColor: Colors.white12,
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final QueueItem item;
  final QueueNotifier notifier;

  const _QueueTile({required this.item, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Color statusColor;
    IconData statusIcon;
    if (item.isDone) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
    } else if (item.isFailed) {
      statusColor = Colors.red;
      statusIcon = Icons.error_rounded;
    } else if (item.isActive) {
      statusColor = cs.primary;
      statusIcon = Icons.downloading_rounded;
    } else {
      statusColor = Colors.white38;
      statusIcon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(item.title, style: tt.bodyLarge)),
              // Cancel / remove buttons
              if (!item.isDone && !item.isFailed)
                TvFocusable(
                  onActivate: () => notifier.cancel(item.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_outlined, size: 16, color: Colors.redAccent),
                        SizedBox(width: 6),
                        Text('Abbrechen', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              if (item.isDone || item.isFailed)
                TvFocusable(
                  onActivate: () => notifier.remove(item.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white38),
                  ),
                ),
            ],
          ),
          if (item.isActive && item.progress > 0) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: item.progress / 100,
              backgroundColor: Colors.white12,
              color: cs.primary,
              borderRadius: BorderRadius.circular(4),
              minHeight: 4,
            ),
          ],
          if (item.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(item.errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
