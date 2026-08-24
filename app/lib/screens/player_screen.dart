import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'download_play_screen.dart';

import '../api/api_service.dart';
import '../models/models.dart';
import '../theme/rs_theme.dart';

/// D-pad focus sections
enum _FocusArea { none, timeline, controls, skip, nextEp, topbar }

/// Number of focusable buttons in the controls row
/// Visual order (left→right): 0=-10  1=play  2=+10  3=next
const _kCtrlCount = 4;

class PlayerScreen extends StatefulWidget {
  final ApiService api;
  final String seriesTitle;
  final int season;
  final int episode;
  final String episodeTitle;
  final int? absoluteEpisode;
  final int? customPathId;
  final String? streamUrl;
  final String? episodeUrl;
  final String? seriesUrl;
  final bool startFromBeginning;

  const PlayerScreen({
    super.key,
    required this.api,
    required this.seriesTitle,
    required this.season,
    required this.episode,
    required this.episodeTitle,
    this.absoluteEpisode,
    this.customPathId,
    this.streamUrl,
    this.episodeUrl,
    this.seriesUrl,
    this.startFromBeginning = false,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  bool _loading = true;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _seekLabelTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _buffering = false;
  Duration? _resumePosition;
  SkipTimes? _skipTimes;
  ThumbnailMeta? _thumbnails;
  String? _seekLabel;

  // Tracks the currently active episode (may change when skipping to next ep)
  late int _activeEpisode;
  String? _activeEpisodeUrl;
  late int _activeSeason;
  late String _activeEpisodeTitle;
  int? _activeAbsoluteEpisode;

  _FocusArea _focusArea = _FocusArea.none;
  int _controlsFocusIdx = 1; // default: play/pause

  // Next-episode auto-advance countdown
  int? _nextEpCountdown;
  bool _nextEpPopupPinned = false; // stays true after countdown is cancelled
  Timer? _countdownTimer;
  // Fullscreen state (desktop only)
  bool _isFullscreen = false;

  // Guard against stale stream events (position/completed) during episode switch
  bool _episodeSwitching = false;
  // True once _player.seek(_resumePosition) has been called; prevents double-seek
  // if the duration stream fires multiple times.
  bool _resumeApplied = false;

  // Accelerated D-pad seeking with preview (seek bar moves, player commits on release)
  Timer? _seekAccelTimer;
  DateTime? _seekHoldStart;
  bool _seekHoldNegative = false;
  Duration? _seekPreview; // null = not scrubbing

  // After _player.seek(), slow devices (Chromecast) briefly re-emit the old
  // position before settling. We suppress those stale events for 2 s.
  Duration? _seekTarget;
  DateTime? _seekIssuedAt;

  // Relative stream file path (e.g. "One Piece/S01E009.m3u8") for thumbnail lookup
  String? _streamFile;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _activeEpisode = widget.episode;
    _activeEpisodeUrl = widget.episodeUrl;
    _activeSeason = widget.season;
    _activeEpisodeTitle = widget.episodeTitle;
    _activeAbsoluteEpisode = widget.absoluteEpisode;
    _player = Player();
    _controller = VideoController(_player);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _seekLabelTimer?.cancel();
    _seekAccelTimer?.cancel();
    _countdownTimer?.cancel();
    _saveProgress(final_: true);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Progress ───────────────────────────────────────────────────────────────

  static String? _extractStreamFile(String url) {
    const prefix = '/api/stream/files/';
    final idx = url.indexOf(prefix);
    if (idx < 0) return null;
    return Uri.decodeComponent(url.substring(idx + prefix.length));
  }

  Future<void> _saveProgress({bool final_ = false}) async {
    final epUrl = _activeEpisodeUrl;
    if (epUrl == null || epUrl.isEmpty) return;
    final dur = _duration.inMilliseconds / 1000.0;
    // If the seek to the resume position hasn't landed yet, use the target
    // resume position rather than the stale 0-second stream value so that
    // a quick exit doesn't wipe out previously saved watch time.
    final pos = _resumePosition != null
        ? _resumePosition!.inMilliseconds / 1000.0
        : _position.inMilliseconds / 1000.0;
    if (dur < 1) return;
    try {
      await widget.api.saveProgress(
        episodeUrl: epUrl,
        seriesTitle: widget.seriesTitle,
        seriesUrl: widget.seriesUrl,
        season: widget.season,
        episodeNumber: _activeEpisode,
        episodeTitle: widget.episodeTitle,
        positionSeconds: pos,
        durationSeconds: dur,
        completed: (pos / dur) > 0.9,
        streamFile: _streamFile,
      );
    } catch (_) {}
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    // Pause before the fullscreen transition — on Windows the native video
    // texture is briefly invalidated during window resize, which freezes the
    // player permanently unless we pause/resume around the mode change.
    final wasPlaying = _isPlaying;
    if (wasPlaying) await _player.pause();
    await windowManager.setFullScreen(next);
    if (!mounted) return;
    setState(() => _isFullscreen = next);
    // Let the new window surface settle before resuming playback.
    await Future.delayed(const Duration(milliseconds: 250));
    if (wasPlaying && mounted) _player.play();
  }

  Future<void> _saveAndPop() async {
    if (_isDesktop && _isFullscreen) await windowManager.setFullScreen(false);
    await _saveProgress(final_: true);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> _initPlayer() async {
    try {
      String streamUrl = widget.streamUrl ?? '';

      if (streamUrl.isEmpty) {
        final library = await widget.api.getLibrary();
        final nTitle = _norm(widget.seriesTitle);
        for (final title in library) {
          if (nTitle.isNotEmpty &&
              !_norm(title.folder).contains(nTitle) &&
              !nTitle.contains(_norm(title.folder))) continue;
          try {
            final url = await widget.api.getStreamUrl(
              folder: title.folder,
              season: widget.season,
              episode: widget.episode,
              customPathId: widget.customPathId,
            );
            if (url.isNotEmpty) {
              streamUrl = url;
              break;
            }
          } catch (_) {}
        }
        if (streamUrl.isEmpty) throw Exception('Episode not found in library');
      }

      _streamFile = _extractStreamFile(streamUrl);

      _subs.add(_player.stream.playing.listen((v) {
        if (mounted) setState(() => _isPlaying = v);
      }));
      _subs.add(_player.stream.position.listen((v) {
        if (!mounted) return;
        // Suppress stale position events for 2 s after a seek.
        // On slow devices (Chromecast) the player briefly re-emits the
        // pre-seek position before settling, causing a visible "jump back".
        final st = _seekTarget;
        if (st != null) {
          final age = DateTime.now().difference(_seekIssuedAt!).inMilliseconds;
          if (age > 2000) {
            _seekTarget = null; // grace period expired, accept all events
          } else if ((v - st).abs() > const Duration(seconds: 3)) {
            return; // stale event — too far from seek target, drop it
          } else {
            _seekTarget = null; // close enough, seek has settled
          }
        }
        setState(() => _position = v);
        // Once the position stream confirms the seek has landed, clear the
        // pending resume so _saveProgress starts using the live position.
        if (_resumePosition != null &&
            v >= _resumePosition! - const Duration(seconds: 5)) {
          _resumePosition = null;
        }
        final rem = (_duration - v).inSeconds;
        if (rem <= 45 && rem > 0 && _duration.inSeconds >= 120 &&
            _nextEpCountdown == null && !_nextEpPopupPinned && !_loading &&
            !_episodeSwitching) {
          _startNextEpCountdown();
        }
      }));
      _subs.add(_player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
        if (v.inMilliseconds > 0 && _resumePosition != null && !_resumeApplied) {
          _resumeApplied = true;
          _player.seek(_resumePosition!);
          // _resumePosition is intentionally kept non-null here so that
          // _saveProgress can use it as a fallback if the user exits before
          // the position stream confirms the seek has landed.
        }
      }));
      _subs.add(_player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }));
      _subs.add(_player.stream.completed.listen((done) {
        if (done && mounted && !_episodeSwitching) _saveAndPop();
      }));

      if (!widget.startFromBeginning && _activeEpisodeUrl?.isNotEmpty == true) {
        try {
          final all = await widget.api.getAllProgress();
          final prog =
              all.where((p) => p.episodeUrl == _activeEpisodeUrl).firstOrNull;
          if (prog != null && !prog.completed && prog.positionSeconds > 30) {
            _resumePosition =
                Duration(milliseconds: (prog.positionSeconds * 1000).round());
          }
        } catch (_) {}
      }

      await _player.open(Media(streamUrl, httpHeaders: _authHeaders()));
      _progressTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());

      if (mounted) {
        setState(() => _loading = false);
        _resetHideTimer();
      }

      _prefetchNextEpisode(); // fire-and-forget

      widget.api
          .getSkipTimes(
              seriesTitle: widget.seriesTitle, episode: _activeEpisode)
          .then((t) {
            if (mounted && t.hasAny) setState(() => _skipTimes = t);
          })
          .catchError((_) {});

      if (streamUrl.isNotEmpty) {
        widget.api
            .getThumbnails(streamUrl: streamUrl)
            .then((t) {
              if (mounted && t != null) setState(() => _thumbnails = t);
            })
            .catchError((_) {});
      }

    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static String _norm(String s) => s
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  // ── Playback control ───────────────────────────────────────────────────────

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying && _seekPreview == null) {
        setState(() {
          _showControls = false;
          _focusArea = _FocusArea.none; // clear focus so it resets on next show
        });
      }
    });
  }

  Map<String, String> _authHeaders() {
    final token = widget.api.authToken;
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  void _togglePlayPause() {
    _player.playOrPause();
    _resetHideTimer();
  }

  void _seek(Duration delta) {
    final raw = _position + delta;
    final target = raw < Duration.zero
        ? Duration.zero
        : (raw > _duration ? _duration : raw);
    _seekTarget = target;
    _seekIssuedAt = DateTime.now();
    _player.seek(target);
    _resetHideTimer();
    final s = delta.inSeconds.abs();
    final label = delta.isNegative ? '$s Sek. zurück' : '$s Sek. vor';
    setState(() { _position = target; _seekLabel = label; });
    _seekLabelTimer?.cancel();
    _seekLabelTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekLabel = null);
    });
  }

  void _seekTo(Duration pos) {
    _seekTarget = pos;
    _seekIssuedAt = DateTime.now();
    setState(() => _position = pos);
    _player.seek(pos);
    _resetHideTimer();
  }

  // ── Accelerated D-pad seeking ──────────────────────────────────────────────

  void _startAccelSeek({required bool negative}) {
    if (_seekAccelTimer != null) return;
    _seekHoldNegative = negative;
    _seekHoldStart = DateTime.now();
    _seekPreview = _position;
    _doAccelSeek(); // immediate first step
    _seekAccelTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _doAccelSeek();
    });
  }

  void _doAccelSeek() {
    final start = _seekHoldStart;
    if (start == null || !mounted) return;
    final elapsedMs = DateTime.now().difference(start).inMilliseconds;
    // Staged steps: 5 s → 10 s → 15 s → 20 s per tick
    final int stepS;
    if (elapsedMs < 800) { stepS = 5; }
    else if (elapsedMs < 1600) { stepS = 10; }
    else if (elapsedMs < 2400) { stepS = 15; }
    else { stepS = 20; }
    final delta = Duration(seconds: _seekHoldNegative ? -stepS : stepS);
    final raw = (_seekPreview ?? _position) + delta;
    final target = raw < Duration.zero
        ? Duration.zero
        : (raw > _duration ? _duration : raw);
    final arrow = _seekHoldNegative ? '←' : '→';
    setState(() {
      _seekPreview = target;
      _seekLabel = '$arrow ${_fmt(target)}';
    });
  }

  void _stopAccelSeek() {
    _seekAccelTimer?.cancel();
    _seekAccelTimer = null;
    _seekHoldStart = null;
    final target = _seekPreview;
    if (target != null) {
      _seekTarget = target;
      _seekIssuedAt = DateTime.now();
      _player.seek(target);
      // Clear preview and optimistically set _position to target in one
      // setState — avoids the flicker caused by preview→null before the
      // position stream confirms the new position.
      setState(() { _seekPreview = null; _position = target; });
    } else {
      _seekPreview = null;
    }
    _seekLabelTimer?.cancel();
    _seekLabelTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _seekLabel = null);
    });
    _resetHideTimer();
  }

  // ── Next episode ──────────────────────────────────────────────────────────

  bool get _showNextEp {
    if (_duration.inSeconds < 1) return false;
    if (_nextEpCountdown != null || _nextEpPopupPinned) return true;
    final remaining = (_duration - _position).inSeconds;
    return remaining >= 45 && remaining <= 120;
  }

  void _startNextEpCountdown() {
    if (!mounted) return;
    setState(() => _nextEpCountdown = 10);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final next = (_nextEpCountdown ?? 1) - 1;
      if (next <= 0) {
        t.cancel();
        _countdownTimer = null;
        setState(() => _nextEpCountdown = null);
        _navigateToNextEpisode();
      } else {
        setState(() => _nextEpCountdown = next);
      }
    });
  }

  // ── Prefetch ───────────────────────────────────────────────────────────────

  /// Silently enqueue the next episode as P1 (prefetch) so it's ready to play
  /// without waiting when the current episode ends.
  Future<void> _prefetchNextEpisode() async {
    final curUrl = _activeEpisodeUrl ?? '';
    final seriesUrl = widget.seriesUrl;
    if (curUrl.isEmpty || seriesUrl == null || seriesUrl.isEmpty) return;

    final nextEp = _activeEpisode + 1;

    final nextEpUrl = curUrl.replaceAllMapped(
        RegExp(r'episode-(\d+)$'), (_) => 'episode-$nextEp');
    if (nextEpUrl == curUrl) return; // URL pattern not recognised

    // Already downloaded?
    final streamUrl = await _findNextEpStreamUrl(nextEp);
    if (streamUrl.isNotEmpty) return;

    // Already queued or running?
    try {
      final existingId = await widget.api.findQueueItemByEpisode(nextEpUrl);
      if (existingId != null) return;
    } catch (_) {}

    // Fetch server defaults for language/provider
    String language = 'German Dub';
    String provider = 'VOE';
    try {
      final settings = await widget.api.getSettings();
      language = settings['default_language'] as String? ?? language;
      provider = settings['default_provider'] as String? ?? provider;
    } catch (_) {}

    // Enqueue as prefetch (priority 1) — fire-and-forget, errors are silently ignored
    try {
      await widget.api.enqueueDownload(
        title: widget.seriesTitle,
        seriesUrl: seriesUrl,
        episodeUrls: [nextEpUrl],
        language: language,
        provider: provider,
        priority: 1,
      );
    } catch (_) {}
  }

  static String _normFolder(String s) => s
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<String> _findNextEpStreamUrl(int nextEp) async {
    try {
      final library = await widget.api.getLibrary();
      final nTitle = _normFolder(widget.seriesTitle);
      for (final title in library) {
        final nFolder = _normFolder(title.folder);
        if (nTitle.isEmpty ||
            (!nFolder.contains(nTitle) && !nTitle.contains(nFolder))) {
          continue;
        }
        try {
          final url = await widget.api.getStreamUrl(
            folder: title.folder,
            season: widget.season,
            episode: nextEp,
            customPathId: widget.customPathId,
          );
          if (url.isNotEmpty) return url;
        } catch (_) {}
      }
    } catch (_) {}
    return '';
  }

  /// Looks up the real title (and absolute episode number, if the backend
  /// resolved one) of episode [episodeNum] within [seasonUrl] via the
  /// episodes list, falling back to a generic label if that fails (e.g.
  /// offline, or the episode isn't listed yet).
  Future<(String title, int? absolute)> _fetchEpisodeMeta(
      String seasonUrl, int episodeNum) async {
    final fallback = 'Folge $episodeNum';
    if (seasonUrl.isEmpty) return (fallback, null);
    try {
      final eps = await widget.api.getEpisodes(seasonUrl);
      for (final ep in eps) {
        if (ep.episodeNumber == episodeNum) {
          return (ep.displayTitle, ep.absoluteEpisodeNumber);
        }
      }
    } catch (_) {}
    return (fallback, null);
  }

  Future<void> _navigateToNextEpisode() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    // Block the position listener from starting another countdown while we
    // await _findNextEpStreamUrl() — on slow devices (Chromecast) that call
    // can take several seconds, during which _nextEpCountdown is null and all
    // other guards are false, causing a second skip to fire.
    _episodeSwitching = true;
    if (mounted) setState(() { _nextEpCountdown = null; _nextEpPopupPinned = false; });

    final nextEp = _activeEpisode + 1;

    // Derive the next episode's AniWorld URL before any async work
    final curEpUrl = _activeEpisodeUrl ?? '';
    final derived = curEpUrl.isNotEmpty
        ? curEpUrl.replaceAllMapped(
            RegExp(r'episode-(\d+)$'), (_) => 'episode-$nextEp')
        : null;
    final nextEpUrl = (derived != curEpUrl) ? derived : null;
    final seasonUrl = curEpUrl.replaceAll(RegExp(r'/episode-\d+/?$'), '');

    // Look up the URL and the real title while the current video is still
    // playing normally — no pause means no Flask thread starvation from the
    // old player.
    final streamUrlFuture = _findNextEpStreamUrl(nextEp);
    final metaFuture = _fetchEpisodeMeta(seasonUrl, nextEp);
    final streamUrl = await streamUrlFuture;
    final (nextEpTitle, nextEpAbsolute) = await metaFuture;
    if (!mounted) return;

    if (streamUrl.isEmpty) {
      // Not yet downloaded → pause and push DownloadPlayScreen on top.
      // We use push (not pushReplacement) so the old PlayerScreen is NOT
      // disposed — its player stays alive but paused, which means it holds
      // no active HLS connections that would starve Waitress threads while
      // DownloadPlayScreen makes its library/queue HTTP calls.
      await _player.pause();
      await _saveProgress(final_: true);
      if (!mounted) return;
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute(
              builder: (_) => DownloadPlayScreen(
                api: widget.api,
                episodeUrl: nextEpUrl ?? '',
                seriesUrl: widget.seriesUrl ?? '',
                seriesTitle: widget.seriesTitle,
                season: _activeSeason,
                episodeNumber: nextEp,
                episodeTitle: nextEpTitle,
                absoluteEpisode: nextEpAbsolute,
                availableLanguages: const [],
                customPathId: widget.customPathId,
                skipResume: true,
              ),
            ),
          )
          .then((_) {
            // When DownloadPlayScreen (and any nested PlayerScreen) pop,
            // close this old PlayerScreen too so the user ends up on the
            // episodes screen rather than back on the ended episode.
            if (mounted) _saveAndPop();
          });
      return;
    }

    await _saveProgress(final_: true);
    if (!mounted) return;

    // Update state for the new episode
    setState(() {
      _activeEpisode = nextEp;
      _activeEpisodeUrl = nextEpUrl;
      _activeEpisodeTitle = nextEpTitle;
      _activeAbsoluteEpisode = nextEpAbsolute;
      _loading = true;
      _position = Duration.zero;
      _duration = Duration.zero;
      _skipTimes = null;
      _thumbnails = null;
      _seekLabel = null;
      _isPlaying = false;
      _nextEpCountdown = null;
      _nextEpPopupPinned = false;
      _buffering = false;
      _focusArea = _FocusArea.none;
      _showControls = true;
    });

    _seekLabelTimer?.cancel();
    _seekLabelTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;

    // Swap media in the existing player — no new Player(), no navigation.
    // _episodeSwitching blocks the position listener and stream.completed from
    // firing the countdown or popping the screen on stale events from the
    // previous episode's media. Reset after 3 s to let the new media settle.
    _episodeSwitching = true;
    _streamFile = _extractStreamFile(streamUrl);
    await _player.open(Media(streamUrl, httpHeaders: _authHeaders()));
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _episodeSwitching = false);
    });
    _progressTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());

    if (mounted) {
      setState(() => _loading = false);
      _resetHideTimer();
    }

    _prefetchNextEpisode(); // prefetch the episode after this one

    widget.api
        .getSkipTimes(seriesTitle: widget.seriesTitle, episode: nextEp)
        .then((t) { if (mounted && t.hasAny) setState(() => _skipTimes = t); })
        .catchError((_) {});
    widget.api
        .getThumbnails(streamUrl: streamUrl)
        .then((t) { if (mounted && t != null) setState(() => _thumbnails = t); })
        .catchError((_) {});
  }

  // ── Skip times ─────────────────────────────────────────────────────────────

  SkipInterval? _activeSkip() {
    if (_skipTimes == null) return null;
    final pos = _position.inMilliseconds / 1000.0;
    final op = _skipTimes!.op;
    final ed = _skipTimes!.ed;
    if (op != null && pos >= op.start && pos < op.end - 2) return op;
    if (ed != null && pos >= ed.start && pos < ed.end - 2) return ed;
    return null;
  }

  String _skipButtonLabel() {
    final pos = _position.inMilliseconds / 1000.0;
    if (_skipTimes?.op != null &&
        pos >= _skipTimes!.op!.start &&
        pos < _skipTimes!.op!.end - 2) return 'Opening überspringen';
    if (_skipTimes?.ed != null &&
        pos >= _skipTimes!.ed!.start &&
        pos < _skipTimes!.ed!.end - 2) return 'Abspann überspringen';
    return '';
  }

  // ── Controls activation ────────────────────────────────────────────────────

  void _activateControl(int idx) {
    switch (idx) {
      case 0:
        _seek(const Duration(seconds: -10));
      case 1:
        _togglePlayPause();
      case 2:
        _seek(const Duration(seconds: 10));
      case 3:
        _navigateToNextEpisode();
    }
  }

  String _controlLabel(int idx) {
    switch (idx) {
      case 0:
        return '10 Sek. zurück';
      case 1:
        return _isPlaying ? 'Pause' : 'Abspielen';
      case 2:
        return '10 Sek. vor';
      case 3:
        return 'Nächste Folge';
      default:
        return '';
    }
  }

  // ── Keyboard ───────────────────────────────────────────────────────────────

  KeyEventResult _handleKey(KeyEvent event) {
    // Stop seek acceleration on key release
    if (event is KeyUpEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        _stopAccelSeek();
      }
      return KeyEventResult.ignored;
    }

    // Suppress OS key-repeat for seek keys — the accel timer handles repetition
    if (event is KeyRepeatEvent) {
      final k = event.logicalKey;
      if ((k == LogicalKeyboardKey.arrowLeft ||
              k == LogicalKeyboardKey.arrowRight) &&
          _focusArea != _FocusArea.controls) {
        return KeyEventResult.handled; // consumed; timer does the work
      }
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Only reset the hide timer for actual key-down events so that key-repeat
    // events don't re-show the UI after it was intentionally hidden.
    _resetHideTimer();

    // Any arrow key cancels the auto-advance countdown
    final k = event.logicalKey;
    if (_nextEpCountdown != null &&
        (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown ||
            k == LogicalKeyboardKey.arrowLeft ||
            k == LogicalKeyboardKey.arrowRight)) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      setState(() { _nextEpCountdown = null; _nextEpPopupPinned = true; });
      return KeyEventResult.handled;
    }

    final skip = _activeSkip();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _stopAccelSeek();
        switch (_focusArea) {
          case _FocusArea.none:
            setState(() => _focusArea = _FocusArea.timeline);
          case _FocusArea.controls:
            setState(() => _focusArea = _FocusArea.timeline);
          case _FocusArea.timeline:
            if (skip != null) {
              setState(() => _focusArea = _FocusArea.skip);
            } else if (_showNextEp) {
              setState(() => _focusArea = _FocusArea.nextEp);
            } else {
              setState(() => _focusArea = _FocusArea.topbar);
            }
          case _FocusArea.skip:
            setState(() => _focusArea = _showNextEp ? _FocusArea.nextEp : _FocusArea.topbar);
          case _FocusArea.nextEp:
            setState(() => _focusArea = _FocusArea.topbar);
          case _FocusArea.topbar:
            break; // already at top
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        _stopAccelSeek();
        switch (_focusArea) {
          case _FocusArea.none:
            setState(() { _focusArea = _FocusArea.controls; _controlsFocusIdx = 1; });
          case _FocusArea.topbar:
            setState(() => _focusArea = _FocusArea.timeline);
          case _FocusArea.timeline:
            setState(() { _focusArea = _FocusArea.controls; _controlsFocusIdx = 1; });
          case _FocusArea.controls:
            // At the bottom of the focus chain → hide UI immediately
            setState(() {
              _showControls = false;
              _focusArea = _FocusArea.none;
            });
          case _FocusArea.skip:
            setState(() => _focusArea = _FocusArea.timeline);
          case _FocusArea.nextEp:
            setState(() => _focusArea = _FocusArea.timeline);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        if (_focusArea == _FocusArea.controls) {
          setState(() =>
              _controlsFocusIdx = math.max(0, _controlsFocusIdx - 1));
        } else {
          // Accelerated seek — timer fires every 100 ms, ramping 1 s→3 s step
          _startAccelSeek(negative: true);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        if (_focusArea == _FocusArea.controls) {
          setState(() => _controlsFocusIdx =
              math.min(_kCtrlCount - 1, _controlsFocusIdx + 1));
        } else {
          _startAccelSeek(negative: false);
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        _stopAccelSeek();
        if (_focusArea == _FocusArea.topbar) {
          _saveAndPop();
        } else if (_focusArea == _FocusArea.nextEp ||
            (_showNextEp && _focusArea == _FocusArea.none)) {
          _navigateToNextEpisode();
        } else if (_focusArea == _FocusArea.skip ||
            (_focusArea == _FocusArea.none && skip != null)) {
          _seekTo(Duration(milliseconds: (skip!.end * 1000).round()));
        } else if (_focusArea == _FocusArea.controls) {
          _activateControl(_controlsFocusIdx);
        } else {
          _togglePlayPause();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        _togglePlayPause();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaRewind:
        _seek(const Duration(seconds: -10));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.mediaFastForward:
        _seek(const Duration(seconds: 10));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
        _stopAccelSeek();
        _saveAndPop();
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final skip = _activeSkip();
    final skipLabel = skip != null ? _skipButtonLabel() : null;

    // Label shown above seek bar: seek feedback, or focused button name
    String? barLabel = _seekLabel;
    if (barLabel == null && _focusArea == _FocusArea.controls) {
      final l = _controlLabel(_controlsFocusIdx);
      if (l.isNotEmpty) barLabel = l;
    }

    final displayPos = _seekPreview ?? _position;
    final progress = _duration.inMilliseconds > 0
        ? (displayPos.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndPop();
      },
      child: MouseRegion(
        onHover: (_) => _resetHideTimer(),
        child: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // ── Video ──────────────────────────────────────────────
                if (!_loading && _error == null)
                  Video(
                    controller: _controller,
                    fill: Colors.black,
                    controls: (_) => const SizedBox.shrink(),
                  ),

                // ── Buffering spinner ──────────────────────────────────
                if (!_loading && _error == null && _buffering)
                  const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 3),
                  ),

                // ── Loading ────────────────────────────────────────────
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                // ── Error ──────────────────────────────────────────────
                if (_error != null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.white54, size: 64),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: Colors.white54),
                              textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                            onPressed: _saveAndPop,
                            child: const Text('Zurück')),
                      ],
                    ),
                  ),

                // ── Controls overlay ───────────────────────────────────
                if (!_loading && _error == null)
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: _PlayerUI(
                      position: displayPos,
                      duration: _duration,
                      progress: progress,
                      isPlaying: _isPlaying,
                      seriesTitle: widget.seriesTitle,
                      season: _activeSeason,
                      episode: _activeEpisode,
                      episodeTitle: _activeEpisodeTitle,
                      absoluteEpisode: _activeAbsoluteEpisode,
                      thumbnails: _thumbnails,
                      focusArea: _focusArea,
                      controlsFocusIdx: _controlsFocusIdx,
                      barLabel: barLabel,
                      timelineFocused: _focusArea == _FocusArea.timeline,
                      topbarFocused: _focusArea == _FocusArea.topbar,
                      onPlayPause: _togglePlayPause,
                      onSeek: _seek,
                      onSeekTo: _seekTo,
                      onBack: _saveAndPop,
                      onNextEp: _navigateToNextEpisode,
                      fmt: _fmt,
                      isDesktop: _isDesktop,
                      isFullscreen: _isFullscreen,
                      onFullscreen: _isDesktop ? _toggleFullscreen : null,
                    ),
                  ),

                // ── Always-visible popups (skip / next episode) ────────
                if (!_loading && _error == null && (skipLabel != null || _showNextEp))
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    right: 32,
                    bottom: _showControls ? 190 : 40,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (skipLabel != null)
                          GestureDetector(
                            onTap: skip != null
                                ? () => _seekTo(Duration(
                                    milliseconds: (skip.end * 1000).round()))
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 13),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: _focusArea == _FocusArea.skip
                                    ? Border.all(color: Rs.accent, width: 3)
                                    : null,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x99000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.skip_next_rounded,
                                      color: Colors.black, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    skipLabel,
                                    style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (skipLabel != null && _showNextEp)
                          const SizedBox(height: 8),
                        if (_showNextEp)
                          GestureDetector(
                            onTap: _navigateToNextEpisode,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 13),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: _focusArea == _FocusArea.nextEp
                                    ? Border.all(color: Rs.accent, width: 3)
                                    : null,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x99000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.skip_next_rounded,
                                      color: Colors.black, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _nextEpCountdown != null
                                        ? 'Nächste Folge ($_nextEpCountdown)'
                                        : 'Nächste Folge',
                                    style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen player UI
// ---------------------------------------------------------------------------

class _PlayerUI extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final double progress;
  final bool isPlaying;
  final String seriesTitle;
  final int season;
  final int episode;
  final String episodeTitle;
  final int? absoluteEpisode;
  final ThumbnailMeta? thumbnails;
  final _FocusArea focusArea;
  final int controlsFocusIdx;
  final String? barLabel;
  final bool timelineFocused;
  final bool topbarFocused;
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;
  final void Function(Duration) onSeekTo;
  final VoidCallback onBack;
  final VoidCallback onNextEp;
  final String Function(Duration) fmt;
  final bool isDesktop;
  final bool isFullscreen;
  final VoidCallback? onFullscreen;

  const _PlayerUI({
    required this.position,
    required this.duration,
    required this.progress,
    required this.isPlaying,
    required this.seriesTitle,
    required this.season,
    required this.episode,
    required this.episodeTitle,
    this.absoluteEpisode,
    this.thumbnails,
    required this.focusArea,
    required this.controlsFocusIdx,
    this.barLabel,
    required this.timelineFocused,
    required this.topbarFocused,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekTo,
    required this.onBack,
    required this.onNextEp,
    required this.fmt,
    required this.isDesktop,
    required this.isFullscreen,
    this.onFullscreen,
  });

  @override
  State<_PlayerUI> createState() => _PlayerUIState();
}

class _PlayerUIState extends State<_PlayerUI> {
  double? _hoverFraction;

  @override
  Widget build(BuildContext context) {
    final remaining = widget.duration - widget.position;
    final previewFraction = _hoverFraction ?? widget.progress;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient background
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xDD000000),
                Color(0x88000000),
                Colors.transparent,
                Colors.transparent,
                Color(0xEE000000),
              ],
              stops: [0, 0.15, 0.28, 0.55, 1],
            ),
          ),
        ),

        // ── Top bar — pinned to top edge ───────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  // Back button — highlighted when topbar is focused
                  GestureDetector(
                    onTap: widget.onBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                      decoration: BoxDecoration(
                        color: widget.topbarFocused
                            ? Rs.accent.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.topbarFocused
                              ? Rs.accent
                              : Colors.white38,
                          width: widget.topbarFocused ? 2.5 : 1.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Zurück',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Fullscreen toggle (desktop only)
                  if (widget.isDesktop && widget.onFullscreen != null) ...[
                    GestureDetector(
                      onTap: widget.onFullscreen,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.white38, width: 1.5),
                        ),
                        child: Icon(
                          widget.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ── Center play/pause circle ────────────────────────────────────────
        Center(
          child: GestureDetector(
            onTap: widget.onPlayPause,
            child: AnimatedOpacity(
              opacity: widget.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 46),
              ),
            ),
          ),
        ),

        // ── Bottom area ─────────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Series info
                Text(
                  widget.absoluteEpisode != null &&
                          widget.absoluteEpisode != widget.episode
                      ? 'STAFFEL ${widget.season} · FOLGE ${widget.episode} · #${widget.absoluteEpisode}'
                      : 'STAFFEL ${widget.season} · FOLGE ${widget.episode}',
                  style: const TextStyle(
                      color: Rs.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.seriesTitle,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.episodeTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.episodeTitle,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 18),

                // Seek bar with thumbnail preview + label above
                LayoutBuilder(builder: (ctx, constraints) {
                  final barWidth = constraints.maxWidth;
                  final thumbW = (widget.thumbnails?.thumbW ?? 160) * 2.0;
                  final thumbH = (widget.thumbnails?.thumbH ?? 90) * 2.0;
                  final rawX = previewFraction * barWidth - thumbW / 2;
                  final previewX = rawX.clamp(0.0, barWidth - thumbW);
                  // Show thumbnail on mouse hover OR when D-pad is on the timeline
                  final showThumb = widget.thumbnails != null &&
                      (_hoverFraction != null || widget.timelineFocused);

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Thumbnail preview on mouse hover
                      if (showThumb)
                        Positioned(
                          bottom: 56 + thumbH / 2,
                          left: previewX,
                          child: _ThumbnailPreview(
                            meta: widget.thumbnails!,
                            // Mouse hover → hover position; D-pad → playback position
                            position: _hoverFraction != null
                                ? Duration(
                                    milliseconds: (_hoverFraction! *
                                            widget.duration.inMilliseconds)
                                        .round())
                                : widget.position,
                          ),
                        ),

                      // Label above seek bar (seek feedback or focused button name)
                      if (widget.barLabel != null)
                        Positioned(
                          bottom: 40,
                          left: (widget.progress * barWidth - 60)
                              .clamp(0.0, barWidth - 140),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.barLabel!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Seek bar
                          _SeekBar(
                            progress: widget.progress,
                            duration: widget.duration,
                            focused: widget.timelineFocused,
                            onSeekTo: widget.onSeekTo,
                            onHoverFraction: (f) =>
                                setState(() => _hoverFraction = f),
                          ),
                          const SizedBox(height: 8),
                          // Time labels
                          Row(
                            children: [
                              Text(
                                widget.fmt(widget.position),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                '-${widget.fmt(remaining)}',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Controls row — three main buttons centered, next on right
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Center group: -10 | play | +10
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // -10s (idx 0)
                                    _CtrlBtn.seek(
                                      icon: Icons.replay_10_rounded,
                                      size: 62,
                                      focused: widget.focusArea ==
                                              _FocusArea.controls &&
                                          widget.controlsFocusIdx == 0,
                                      onTap: () => widget.onSeek(
                                          const Duration(seconds: -10)),
                                    ),
                                    const SizedBox(width: 18),
                                    // Play/Pause (idx 1) — large orange
                                    _CtrlBtn.play(
                                      isPlaying: widget.isPlaying,
                                      size: 74,
                                      focused: widget.focusArea ==
                                              _FocusArea.controls &&
                                          widget.controlsFocusIdx == 1,
                                      onTap: widget.onPlayPause,
                                    ),
                                    const SizedBox(width: 18),
                                    // +10s (idx 2)
                                    _CtrlBtn.seek(
                                      icon: Icons.forward_10_rounded,
                                      size: 62,
                                      focused: widget.focusArea ==
                                              _FocusArea.controls &&
                                          widget.controlsFocusIdx == 2,
                                      onTap: () => widget.onSeek(
                                          const Duration(seconds: 10)),
                                    ),
                                  ],
                                ),
                              ),
                              // Next episode (idx 3) — right side
                              _CtrlBtn.square(
                                icon: Icons.skip_next_rounded,
                                size: 50,
                                focused: widget.focusArea ==
                                        _FocusArea.controls &&
                                    widget.controlsFocusIdx == 3,
                                onTap: widget.onNextEp,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Seek bar
// ---------------------------------------------------------------------------

class _SeekBar extends StatelessWidget {
  final double progress;
  final Duration duration;
  final bool focused;
  final void Function(Duration) onSeekTo;
  final void Function(double?) onHoverFraction;

  const _SeekBar({
    required this.progress,
    required this.duration,
    required this.focused,
    required this.onSeekTo,
    required this.onHoverFraction,
  });

  void _seekAt(BuildContext context, Offset localPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final fraction = (localPos.dx / box.size.width).clamp(0.0, 1.0);
    onSeekTo(Duration(
        milliseconds: (fraction * duration.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final trackH = focused ? 6.0 : 4.0;

    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onHoverFraction(
            (e.localPosition.dx / box.size.width).clamp(0.0, 1.0));
      },
      onExit: (_) => onHoverFraction(null),
      child: GestureDetector(
        onTapDown: (d) => _seekAt(context, d.localPosition),
        onHorizontalDragUpdate: (d) => _seekAt(context, d.localPosition),
        child: SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.center,
            child: LayoutBuilder(
              builder: (_, c) => Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track background
                  Container(
                    height: trackH,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(trackH),
                    ),
                  ),
                  // Filled portion (orange)
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: trackH,
                      decoration: BoxDecoration(
                        color: Rs.accent,
                        borderRadius: BorderRadius.circular(trackH),
                      ),
                    ),
                  ),
                  // Thumb dot
                  Positioned(
                    left: (c.maxWidth * progress - 9)
                        .clamp(0.0, c.maxWidth - 18),
                    top: -(9 - trackH / 2),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: focused ? Rs.accent : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x66000000), blurRadius: 6)
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Control buttons
// ---------------------------------------------------------------------------

class _CtrlBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _CtrlBtn({required this.child, required this.onTap});

  /// Large orange play/pause button
  factory _CtrlBtn.play({
    required bool isPlaying,
    required bool focused,
    required VoidCallback onTap,
    double size = 64,
  }) =>
      _CtrlBtn(
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Rs.accent,
              shape: BoxShape.circle,
              border: focused
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Rs.accent.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: size * 0.48,
            ),
          ),
        ),
      );

  /// Circular seek button (-10 / +10)
  factory _CtrlBtn.seek({
    required IconData icon,
    required bool focused,
    required VoidCallback onTap,
    double size = 52,
  }) =>
      _CtrlBtn(
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: focused
                    ? Rs.accent
                    : Colors.white.withValues(alpha: 0.20),
                width: focused ? 2.5 : 1.5,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.46),
          ),
        ),
      );

  /// Square rounded secondary button (next)
  factory _CtrlBtn.square({
    required IconData icon,
    required bool focused,
    required VoidCallback onTap,
    double size = 46,
  }) =>
      _CtrlBtn(
        onTap: onTap,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? Rs.accent
                    : Colors.white.withValues(alpha: 0.20),
                width: focused ? 2.5 : 1.5,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.44),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => child;
}

// ---------------------------------------------------------------------------
// Thumbnail preview widget
// ---------------------------------------------------------------------------

class _ThumbnailPreview extends StatelessWidget {
  final ThumbnailMeta meta;
  final Duration position;

  const _ThumbnailPreview({required this.meta, required this.position});

  @override
  Widget build(BuildContext context) {
    final frame = meta.frameAt(position);
    final col = frame % meta.cols;
    final row = frame ~/ meta.cols;
    const scale = 2.0;
    final dW = meta.thumbW * scale;
    final dH = meta.thumbH * scale;
    final totalW = meta.cols * dW;
    final totalH = meta.rows * dH;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: dW,
        height: dH,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white30, width: 1.5),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
                color: Color(0x99000000),
                blurRadius: 12,
                offset: Offset(0, 4))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: totalW,
            maxHeight: totalH,
            child: Transform.translate(
              offset: Offset(-col * dW, -row * dH),
              child: CachedNetworkImage(
                imageUrl: meta.spriteUrl,
                width: totalW,
                height: totalH,
                fit: BoxFit.fill,
                placeholder: (_, _) => Container(color: Colors.black45),
                errorWidget: (_, _, _) => Container(color: Colors.black45),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
