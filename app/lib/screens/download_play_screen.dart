import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'player_screen.dart';

/// Click an episode → check all library folders for a working stream URL.
///   - Found  → navigate to PlayerScreen immediately (with the URL).
///   - Not found → enqueue download with German Dub / VOE, show progress.
///     When queue item is done → re-check all folders → navigate when found.
///
/// Returns [true] via Navigator.pop / pushReplacement result so the calling
/// EpisodesScreen knows it should refresh its episode list.
class DownloadPlayScreen extends ConsumerStatefulWidget {
  final ApiService api;
  final String episodeUrl;
  final String seriesUrl;
  final String seriesTitle;
  final int season;
  final int episodeNumber;
  final String episodeTitle;
  final List<String> availableLanguages;
  final int? customPathId;

  const DownloadPlayScreen({
    super.key,
    required this.api,
    required this.episodeUrl,
    required this.seriesUrl,
    required this.seriesTitle,
    required this.season,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.availableLanguages,
    this.customPathId,
  });

  @override
  ConsumerState<DownloadPlayScreen> createState() => _DownloadPlayScreenState();
}

class _DownloadPlayScreenState extends ConsumerState<DownloadPlayScreen> {
  bool _checking = true;
  int? _queueId;
  bool _navigating = false;
  bool _hasEverFoundItem = false;
  String? _error;
  // Safety-net: poll the library every 3 s so we react immediately when the
  // file is available, regardless of which queue item produced it.
  Timer? _libraryPoller;

  @override
  void initState() {
    super.initState();
    _checkThenMaybeEnqueue();
  }

  @override
  void dispose() {
    _libraryPoller?.cancel();
    super.dispose();
  }

  // ── Stream URL resolution ──────────────────────────────────────────────────

  /// Strips year "(2012)", IMDB tags "[imdbid-...]", lowercases and removes
  /// all non-alphanumeric characters so titles can be compared fuzzily.
  static String _normalize(String s) => s
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Returns true if [folderName] belongs to this series.
  /// Compares normalized folder vs normalized series title – handles spacing,
  /// casing, and partial matches (e.g. "High School DxD New" ↔ "High School DxD").
  bool _folderMatchesSeries(String folderName) {
    final nFolder = _normalize(folderName);
    final nTitle = _normalize(widget.seriesTitle);
    if (nTitle.isEmpty || nFolder.isEmpty) return false;
    return nFolder.contains(nTitle) || nTitle.contains(nFolder);
  }

  /// Searches only library folders that match this series.
  /// Returns the first working .m3u8 URL, or '' if not found.
  Future<String> _findStreamUrl() async {
    try {
      final library = await widget.api.getLibrary();
      for (final title in library) {
        if (!_folderMatchesSeries(title.folder)) continue;
        try {
          final url = await widget.api.getStreamUrl(
            folder: title.folder,
            season: widget.season,
            episode: widget.episodeNumber,
            customPathId: widget.customPathId,
          );
          if (url.isNotEmpty) return url;
        } catch (_) {
          // 404 → try next matching folder
        }
      }
    } catch (_) {}
    return '';
  }

  // ── Phase 1: check + maybe enqueue ────────────────────────────────────────

  Future<void> _checkThenMaybeEnqueue() async {
    final streamUrl = await _findStreamUrl();
    if (!mounted) return;

    if (streamUrl.isNotEmpty) {
      _navigateTo(streamUrl);
      return;
    }

    setState(() => _checking = false);

    // If the episode is already downloading, adopt that item instead of
    // creating a duplicate (which would waste bandwidth and delay playback).
    final existingId = await widget.api.findQueueItemByEpisode(widget.episodeUrl);
    if (!mounted) return;

    if (existingId != null) {
      setState(() => _queueId = existingId);
    } else {
      await _autoEnqueue();
    }

    _startLibraryPoller();
  }

  void _startLibraryPoller() {
    _libraryPoller?.cancel();
    _libraryPoller = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_navigating || !mounted) {
        _libraryPoller?.cancel();
        return;
      }
      final url = await _findStreamUrl();
      if (url.isNotEmpty && mounted && !_navigating) {
        _libraryPoller?.cancel();
        _onDownloadDone();
      }
    });
  }

  Future<void> _autoEnqueue() async {
    try {
      final lang = widget.availableLanguages.contains('German Dub')
          ? 'German Dub'
          : (widget.availableLanguages.firstOrNull ?? 'German Dub');

      final id = await widget.api.enqueueDownload(
        title: widget.seriesTitle,
        seriesUrl: widget.seriesUrl,
        episodeUrls: [widget.episodeUrl],
        language: lang,
        provider: 'VOE',
        priority: 0, // watch-intent: user is waiting to watch immediately
      );
      if (mounted) setState(() => _queueId = id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ── Cancel ─────────────────────────────────────────────────────────────────

  Future<void> _cancelDownload() async {
    final id = _queueId;
    if (id == null) return;
    try {
      await widget.api.cancelQueueItem(id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  // ── Phase 2: called when queue item transitions to done ───────────────────

  void _onDownloadDone() {
    if (_navigating || !mounted) return;
    _navigating = true;
    _libraryPoller?.cancel();
    _findStreamUrl().then((url) {
      if (!mounted) return;
      if (url.isNotEmpty) {
        _navigateTo(url);
      } else {
        // Download marked done but .m3u8 not found yet – retry once after delay
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          _findStreamUrl().then((url2) {
            if (!mounted) return;
            if (url2.isNotEmpty) {
              _navigateTo(url2);
            } else {
              setState(() {
                _navigating = false;
                _error = 'Download completed but playback file not found';
              });
            }
          });
        });
      }
    });
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigateTo(String streamUrl) {
    if (!mounted) return;
    _navigating = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PlayerScreen(
            api: widget.api,
            seriesTitle: widget.seriesTitle,
            season: widget.season,
            episode: widget.episodeNumber,
            episodeTitle: widget.episodeTitle,
            customPathId: widget.customPathId,
            streamUrl: streamUrl,
            episodeUrl: widget.episodeUrl,
            seriesUrl: widget.seriesUrl,
          ),
        ))
        .then((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Phase 1: just a spinner while we check
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }

    // Phase 2: listen for queue updates
    final queueId = _queueId;

    ref.listen<QueueState>(queueProvider, (_, next) {
      if (_navigating || queueId == null) return;
      final item = next.items.where((i) => i.id == queueId).firstOrNull;
      if (item != null) _hasEverFoundItem = true;
      if (item?.isDone == true || (_hasEverFoundItem && item == null)) {
        _onDownloadDone();
      }
    });

    final queueState = ref.watch(queueProvider);
    final item = queueId != null
        ? queueState.items.where((i) => i.id == queueId).firstOrNull
        : null;
    if (item != null) _hasEverFoundItem = true;

    final ffmpeg = queueState.ffmpeg;
    final status = item?.status ?? 'queued';
    final isRunning = status == 'running';
    final isFailed = item?.isFailed ?? false;
    final hasError = _error != null || isFailed;

    double? progressValue;
    String statusText;
    String detail = '';

    if (_error != null) {
      statusText = 'Could not start download';
      detail = _error!;
    } else if (queueId == null) {
      statusText = 'Starting download...';
    } else if (isFailed) {
      statusText = 'Download failed';
      detail = item?.errorMessage ?? '';
    } else if (isRunning && ffmpeg.active) {
      progressValue = (ffmpeg.percent / 100.0).clamp(0.0, 1.0);
      statusText = 'Downloading...';
      final parts = <String>[
        if (ffmpeg.time.isNotEmpty) ffmpeg.time,
        if (ffmpeg.bandwidth.isNotEmpty) ffmpeg.bandwidth,
        if (ffmpeg.speed.isNotEmpty) ffmpeg.speed,
      ];
      detail = parts.join('  ·  ');
    } else if (isRunning) {
      statusText = 'Downloading...';
    } else {
      statusText = 'Waiting in queue...';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusable(
                    autofocus: true,
                    onActivate: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded, color: Colors.white70),
                          SizedBox(width: 8),
                          Text('Back',
                              style: TextStyle(color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  if (queueId != null && !_navigating) ...[
                    const SizedBox(width: 16),
                    TvFocusable(
                      onActivate: _cancelDownload,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 20),
                            SizedBox(width: 8),
                            Text('Abbrechen',
                                style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const Spacer(),

              Text(widget.seriesTitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                widget.episodeTitle,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              if (!hasError) ...[
                LinearProgressIndicator(
                  value: progressValue,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(statusText,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16)),
                    if (progressValue != null) ...[
                      const Spacer(),
                      Text(
                        '${ffmpeg.percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(detail,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 14)),
                ],
              ] else ...[
                Text(statusText,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 16)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detail,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 14)),
                ],
                const SizedBox(height: 24),
                TvFocusable(
                  onActivate: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Go back',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
