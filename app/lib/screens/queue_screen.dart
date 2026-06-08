import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';

class QueueScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  const QueueScreen({super.key, required this.nav});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  final _scrollCtrl = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

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
            alignment: 0.2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(queueProvider);
    final notifier = ref.read(queueProvider.notifier);
    final tt = Theme.of(context).textTheme;

    final completed = state.items.where((i) => i.isDone || i.isFailed).toList();
    final active = state.items.where((i) => !i.isDone && !i.isFailed).toList();
    final hasCompleted = completed.isNotEmpty;

    // Nav: row 0 = "Clear completed" (if exists), rows N = one per queue item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav(
        [
          if (hasCompleted) 1,
          ...state.items.map((_) => 1),
        ],
        (row, col) {
          if (hasCompleted && row == 0) {
            notifier.clearCompleted();
            return;
          }
          final idx = hasCompleted ? row - 1 : row;
          if (idx >= 0 && idx < state.items.length) {
            final item = state.items[idx];
            if (item.isDone || item.isFailed) {
              notifier.remove(item.id);
            } else {
              notifier.cancel(item.id);
            }
          }
        },
      );
    });

    int navRowFor(QueueItem item) {
      final baseIdx = state.items.indexOf(item);
      return hasCompleted ? 1 + baseIdx : baseIdx;
    }

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
              if (hasCompleted)
                ListenableBuilder(
                  listenable: widget.nav,
                  builder: (_, _) {
                    final isFoc = widget.nav.isItemFocused(0, 0);
                    return GestureDetector(
                      onTap: notifier.clearCompleted,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        child: const Text('Clear completed',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    );
                  },
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
                      const Icon(Icons.download_done_rounded,
                          size: 64, color: Colors.white12),
                      const SizedBox(height: 16),
                      Text('Queue is empty',
                          style: tt.bodyLarge?.copyWith(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  children: [
                    if (active.isNotEmpty) ...[
                      Text('Active',
                          style: tt.titleMedium
                              ?.copyWith(color: Colors.white54)),
                      const SizedBox(height: 8),
                      ...active.map((item) =>
                          _buildItem(context, item, notifier, navRowFor(item))),
                      const SizedBox(height: 24),
                    ],
                    if (hasCompleted) ...[
                      Text('Completed',
                          style: tt.titleMedium
                              ?.copyWith(color: Colors.white54)),
                      const SizedBox(height: 8),
                      ...completed.map((item) =>
                          _buildItem(context, item, notifier, navRowFor(item))),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext context, QueueItem item,
      QueueNotifier notifier, int navRow) {
    Color statusColor;
    IconData statusIcon;
    if (item.isDone) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
    } else if (item.isFailed) {
      statusColor = Colors.red;
      statusIcon = Icons.error_rounded;
    } else if (item.isActive) {
      statusColor = Rs.accent;
      statusIcon = Icons.downloading_rounded;
    } else {
      statusColor = Colors.white38;
      statusIcon = Icons.schedule_rounded;
    }

    return ListenableBuilder(
      listenable: widget.nav,
      builder: (_, _) {
        final isFoc = widget.nav.isItemFocused(navRow, 0);
        return GestureDetector(
          onTap: () {
            if (item.isDone || item.isFailed) {
              notifier.remove(item.id);
            } else {
              notifier.cancel(item.id);
            }
          },
          child: AnimatedContainer(
            key: _rowKeys.putIfAbsent(navRow, GlobalKey.new),
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFoc
                  ? Rs.accent.withValues(alpha: 0.10)
                  : const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFoc ? Rs.accent : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: isFoc
                  ? [BoxShadow(color: Rs.glow(0.2), blurRadius: 10)]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                    // Action hint
                    if (!item.isDone && !item.isFailed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_outlined,
                              size: 15,
                              color: Colors.redAccent
                                  .withValues(alpha: isFoc ? 1.0 : 0.55)),
                          const SizedBox(width: 5),
                          Text('Abbrechen',
                              style: TextStyle(
                                  color: Colors.redAccent
                                      .withValues(alpha: isFoc ? 1.0 : 0.55),
                                  fontSize: 13)),
                        ],
                      )
                    else
                      Icon(Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white38
                              .withValues(alpha: isFoc ? 1.0 : 0.6)),
                  ],
                ),
                if (item.isActive && item.progress > 0) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: item.progress / 100,
                    backgroundColor: Colors.white12,
                    color: Rs.accent,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 4,
                  ),
                ],
                if (item.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(item.errorMessage!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FfmpegBanner extends StatelessWidget {
  final FfmpegProgress progress;
  const _FfmpegBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Rs.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Rs.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                  width: 10,
                  height: 10,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Rs.accent)),
              const SizedBox(width: 10),
              Text(
                  'Downloading — ${progress.percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Rs.text)),
              const Spacer(),
              Text('${progress.time}  ${progress.speed}  ${progress.bandwidth}',
                  style: const TextStyle(color: Rs.muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.percent / 100,
            backgroundColor: Colors.white12,
            color: Rs.accent,
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}
