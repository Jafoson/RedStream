import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'download_play_screen.dart';
import 'player_screen.dart';

class EpisodesScreen extends ConsumerStatefulWidget {
  final String seasonUrl;
  final String seriesUrl;
  final String seriesTitle;
  final Season season;

  const EpisodesScreen({
    super.key,
    required this.seasonUrl,
    required this.seriesUrl,
    required this.seriesTitle,
    required this.season,
  });

  @override
  ConsumerState<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends ConsumerState<EpisodesScreen> {
  List<Episode> _episodes = [];
  Map<String, List<String>> _providers = {};
  bool _loading = true;
  String? _error;

  String _selectedLanguage = 'German Dub';
  String _selectedProvider = 'VOE';

  @override
  void initState() {
    super.initState();
    _load();
    _loadPreferredLanguage();
  }

  Future<void> _load() async {
    final api = ref.read(apiServiceProvider);
    try {
      final eps = await api.getEpisodes(widget.seasonUrl);
      if (mounted) setState(() { _episodes = eps; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadPreferredLanguage() async {
    final lang = await ref
        .read(apiServiceProvider)
        .getPreferredLanguage(seriesUrl: widget.seriesUrl);
    if (mounted) setState(() => _selectedLanguage = lang);
  }

  static String _fmtSeconds(double s) {
    final t = Duration(milliseconds: (s * 1000).round());
    final h = t.inHours;
    final m = t.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = t.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  Future<void> _loadProviders(String episodeUrl) async {
    final api = ref.read(apiServiceProvider);
    try {
      final p = await api.getProviders(episodeUrl);
      if (mounted) setState(() => _providers = p);
    } catch (_) {}
  }

  // ── Play a downloaded episode directly ─────────────────────────────────────

  void _playEpisode(Episode ep) {
    final api = ref.read(apiServiceProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          api: api,
          seriesTitle: widget.seriesTitle,
          season: widget.season.seasonNumber,
          episode: ep.episodeNumber,
          episodeTitle: ep.displayTitle,
          absoluteEpisode: ep.absoluteEpisodeNumber,
          episodeUrl: ep.url,
          seriesUrl: widget.seriesUrl,
        ),
      ),
    );
  }

  // ── Tap on episode row ──────────────────────────────────────────────────────
  // Always go through DownloadPlayScreen. It checks if the file is really on
  // disk first (getStreamUrl), plays immediately if yes, downloads if no.
  // This handles the case where ep.downloaded is stale (e.g. only .ts segments
  // but no .m3u8 present from a previous partial download).

  void _handleEpisodeTap(Episode ep) {
    final api = ref.read(apiServiceProvider);
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => DownloadPlayScreen(
              api: api,
              episodeUrl: ep.url,
              seriesUrl: widget.seriesUrl,
              seriesTitle: widget.seriesTitle,
              season: widget.season.seasonNumber,
              episodeNumber: ep.episodeNumber,
              episodeTitle: ep.displayTitle,
              absoluteEpisode: ep.absoluteEpisodeNumber,
              availableLanguages: ep.availableLanguages,
            ),
          ),
        )
        .then((downloaded) {
          // Reload episode list to refresh the "Downloaded" badge
          if ((downloaded ?? false) && mounted) _load();
        });
  }

  // ── Download-only dialog (Download button) ──────────────────────────────────

  Future<void> _showDownloadDialog(Episode ep) async {
    await _loadProviders(ep.url);
    if (!mounted) return;

    final langs = _providers.keys.toList();
    if (langs.isNotEmpty && !langs.contains(_selectedLanguage)) {
      setState(() => _selectedLanguage = langs.first);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => _DownloadDialog(
        episode: ep,
        seriesTitle: widget.seriesTitle,
        seriesUrl: widget.seriesUrl,
        providers: _providers,
        initialLanguage: _selectedLanguage,
        initialProvider: _selectedProvider,
        confirmLabel: 'Download',
        onDownload: (lang, provider) {
          setState(() { _selectedLanguage = lang; _selectedProvider = provider; });
          ref.read(apiServiceProvider).enqueueDownload(
            title: widget.seriesTitle,
            seriesUrl: widget.seriesUrl,
            episodeUrls: [ep.url],
            language: lang,
            provider: provider,
          ).then((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Added "${ep.displayTitle}" to queue')),
              );
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.seriesTitle} — ${widget.season.label}'),
        leading: TvFocusable(
          onActivate: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(8),
          child: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.white54)))
              : ListView.separated(
                  padding: const EdgeInsets.all(32),
                  itemCount: _episodes.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0xFF2A2A2A), height: 1),
                  itemBuilder: (context, i) {
                    final ep = _episodes[i];
                    return TvFocusable(
                      autofocus: i == 0,
                      onActivate: () => _handleEpisodeTap(ep),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Episode number
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                                    style: tt.titleMedium?.copyWith(
                                      color: ep.isWatched
                                          ? Colors.white38
                                          : cs.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Title + languages
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ep.displayTitle,
                                        style: tt.bodyLarge?.copyWith(
                                          color: ep.isWatched
                                              ? Colors.white38
                                              : null,
                                        ),
                                      ),
                                      if (ep.availableLanguages.isNotEmpty)
                                        Text(
                                          ep.availableLanguages.join(' · '),
                                          style: tt.bodyMedium
                                              ?.copyWith(fontSize: 13),
                                        ),
                                      if (ep.absoluteEpisodeNumber != null &&
                                          ep.absoluteEpisodeNumber !=
                                              ep.episodeNumber)
                                        Text(
                                          'Episode #${ep.absoluteEpisodeNumber} gesamt',
                                          style: tt.bodyMedium?.copyWith(
                                              fontSize: 12,
                                              color: Colors.white54),
                                        ),
                                    ],
                                  ),
                                ),
                                // Watched badge
                                if (ep.isWatched)
                                  Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4FC3F7)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Gesehen',
                                        style: TextStyle(
                                            color: Color(0xFF4FC3F7),
                                            fontSize: 13)),
                                  ),
                                // Downloaded badge
                                if (ep.downloaded && !ep.isWatched)
                                  Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: const Text('✓ Downloaded',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 13)),
                                  ),
                                // Play button (only for downloaded)
                                if (ep.downloaded)
                                  _ActionBtn(
                                    icon: ep.isPartiallyWatched
                                        ? Icons.play_circle_outline_rounded
                                        : Icons.play_arrow_rounded,
                                    label: ep.isPartiallyWatched
                                        ? 'Fortsetzen'
                                        : 'Play',
                                    color: cs.primary,
                                    onActivate: () => _playEpisode(ep),
                                  ),
                                const SizedBox(width: 8),
                                // Download button (always visible)
                                _ActionBtn(
                                  icon: Icons.download_rounded,
                                  label: ep.downloaded
                                      ? 'Re-download'
                                      : 'Download',
                                  color: Colors.white60,
                                  onActivate: () =>
                                      _showDownloadDialog(ep),
                                ),
                              ],
                            ),
                            // Progress bar for partially watched episodes
                            if (ep.isPartiallyWatched) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const SizedBox(width: 64),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: ep.watchProgress,
                                        backgroundColor: Colors.white12,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                                Color(0xFF4FC3F7)),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ab ${_fmtSeconds(ep.watchPosition)}',
                                    style: const TextStyle(
                                        color: Color(0xFF4FC3F7), fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button widget
// ---------------------------------------------------------------------------

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onActivate;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onActivate: onActivate,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared download dialog
// ---------------------------------------------------------------------------

class _DownloadDialog extends StatefulWidget {
  final Episode episode;
  final String seriesTitle;
  final String seriesUrl;
  final Map<String, List<String>> providers;
  final String initialLanguage;
  final String initialProvider;
  final String confirmLabel;
  final void Function(String lang, String provider) onDownload;

  const _DownloadDialog({
    required this.episode,
    required this.seriesTitle,
    required this.seriesUrl,
    required this.providers,
    required this.initialLanguage,
    required this.initialProvider,
    required this.confirmLabel,
    required this.onDownload,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  late String _lang;
  late String _provider;

  @override
  void initState() {
    super.initState();
    _lang = widget.providers.containsKey(widget.initialLanguage)
        ? widget.initialLanguage
        : (widget.providers.keys.firstOrNull ?? widget.initialLanguage);
    final provs = widget.providers[_lang] ?? [];
    _provider = provs.contains(widget.initialProvider)
        ? widget.initialProvider
        : (provs.firstOrNull ?? widget.initialProvider);
  }

  List<String> get _providerList => widget.providers[_lang] ?? [];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1C),
      title: Text(widget.confirmLabel, style: tt.titleLarge),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.episode.displayTitle, style: tt.bodyLarge),
            const SizedBox(height: 24),
            Text('Language', style: tt.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.providers.keys.map((lang) {
                final sel = lang == _lang;
                return TvFocusable(
                  onActivate: () {
                    setState(() {
                      _lang = lang;
                      final p = widget.providers[lang] ?? [];
                      if (!p.contains(_provider)) {
                        _provider = p.firstOrNull ?? _provider;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(lang,
                        style: TextStyle(
                            color:
                                sel ? Colors.black : Colors.white70)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Provider', style: tt.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _providerList.map((p) {
                final sel = p == _provider;
                return TvFocusable(
                  onActivate: () => setState(() => _provider = p),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? cs.primary.withValues(alpha: 0.2)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          sel ? Border.all(color: cs.primary) : null,
                    ),
                    child: Text(p,
                        style: TextStyle(
                            color:
                                sel ? cs.primary : Colors.white70)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TvFocusable(
          onActivate: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
        ),
        TvFocusable(
          autofocus: true,
          onActivate: () {
            Navigator.of(context).pop();
            widget.onDownload(_lang, _provider);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.confirmLabel,
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
