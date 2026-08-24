import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/models.dart';
import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/tv_keyboard_dialog.dart';
import 'setup_screen.dart';
import 'web_access_screen.dart';

bool get _supportsUpdate =>
    !kIsWeb &&
    (Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isAndroid);

class SettingsScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  const SettingsScreen({super.key, required this.nav});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late String _url;
  final _urlFocus = FocusNode(skipTraversal: true);
  bool _saved = false;
  String _appVersion = '';
  StorageStats? _storage;
  bool _storageLoading = true;

  @override
  void initState() {
    super.initState();
    _url = ref.read(serverUrlProvider);
    _loadVersion();
    _loadStorage();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _loadStorage() async {
    try {
      final stats = await ref.read(apiServiceProvider).getStorageStats();
      if (mounted) setState(() { _storage = stats; _storageLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _storageLoading = false);
    }
  }

  @override
  void dispose() {
    widget.nav.textInputActive = false;
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    await ref.read(serverUrlProvider.notifier).setUrl(_url);
    if (mounted) setState(() => _saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final currentUrl = ref.watch(serverUrlProvider);
    final updateState = ref.watch(updateProvider);

    // Nav rows match visual top-to-bottom order:
    //   0 = URL field, 1 = Save, 2 = Update btn (if shown), 3 = Reconfigure
    // Without update support: 0 = URL, 1 = Save, 2 = Reconfigure
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_supportsUpdate) {
        widget.nav.registerNav([1, 1, 1, 1], (row, col) {
          switch (row) {
            case 0: _urlFocus.requestFocus();
            case 1: _saveUrl();
            case 2: _handleUpdateAction(updateState);
            case 3:
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const SetupScreen()),
              );
          }
        });
      } else if (kIsWeb) {
        widget.nav.registerNav([1], (row, col) {
          if (row == 0) _disconnectWeb();
        });
      } else {
        widget.nav.registerNav([1, 1, 1], (row, col) {
          switch (row) {
            case 0: _urlFocus.requestFocus();
            case 1: _saveUrl();
            case 2:
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const SetupScreen()),
              );
          }
        });
      }
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      children: [
        Text('Settings', style: tt.displayMedium),
        const SizedBox(height: 40),

        // ── Server URL (not applicable to the web build: it is always
        //    same-origin with the backend that serves it) ─────────────────
        if (!kIsWeb) ...[
        _Section(
          title: 'Server',
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Server URL', style: tt.bodyLarge),
                  if (currentUrl.isNotEmpty)
                    Text(currentUrl, style: tt.bodyMedium),
                  const SizedBox(height: 14),
                  TvTextInput(
                    label: 'http://192.168.1.100:8080',
                    value: _url,
                    focusNode: _urlFocus,
                    onChanged: (v) => setState(() => _url = v),
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: widget.nav,
                    builder: (_, _) {
                      final isFoc = widget.nav.isItemFocused(1, 0);
                      return GestureDetector(
                        onTap: _saveUrl,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 13),
                          decoration: BoxDecoration(
                            color: _saved
                                ? Colors.green
                                : isFoc
                                    ? Rs.accent
                                    : Rs.panel3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFoc && !_saved
                                  ? Rs.accent
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                            boxShadow: isFoc
                                ? [
                                    BoxShadow(
                                        color: Rs.glow(0.35),
                                        blurRadius: 14)
                                  ]
                                : null,
                          ),
                          child: Text(
                            _saved ? '✓ Gespeichert' : 'Speichern',
                            style: TextStyle(
                              color: (isFoc || _saved) ? Rs.bg : Rs.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        ],

        // ── Storage ──────────────────────────────────────────────────────
        _Section(
          title: 'Speicher',
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: _storageLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Rs.accent),
                      ),
                    )
                  : (_storage == null || _storage!.roots.isEmpty)
                      ? Text('Speicherinfo nicht verfügbar',
                          style: tt.bodyMedium?.copyWith(color: Colors.white38))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final root in _storage!.roots) ...[
                              _StorageUsageRow(
                                  root: root,
                                  showLabel: _storage!.roots.length > 1),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // ── Updates (desktop only) ──────────────────────────────────────
        if (_supportsUpdate) ...[
          _Section(
            title: 'Updates',
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('RedStream',
                                  style: tt.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700)),
                              Text(
                                _appVersion.isEmpty
                                    ? 'Version wird geladen…'
                                    : 'v$_appVersion',
                                style: tt.bodyMedium
                                    ?.copyWith(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        _UpdateStatusChip(state: updateState),
                      ],
                    ),
                    if (updateState is UpdateAvailable) ...[
                      const SizedBox(height: 12),
                      _ReleaseNotes(body: updateState.release.body),
                    ],
                    if (updateState is UpdateDownloading) ...[
                      const SizedBox(height: 16),
                      _DownloadProgress(progress: updateState.progress),
                    ],
                    if (updateState is UpdateError) ...[
                      const SizedBox(height: 10),
                      Text(
                        updateState.message,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: widget.nav,
                      builder: (_, _) {
                        final isFoc = widget.nav.isItemFocused(2, 0);
                        return _UpdateButton(
                          state: updateState,
                          isFocused: isFoc,
                          onPressed: () => _handleUpdateAction(updateState),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],

        // ── Connection ──────────────────────────────────────────────────
        _Section(
          title: 'Verbindung',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: widget.nav,
                builder: (_, _) {
                  final isFoc = kIsWeb
                      ? widget.nav.isItemFocused(0, 0)
                      : widget.nav.isItemFocused(3, 0);
                  return GestureDetector(
                    onTap: kIsWeb
                        ? _disconnectWeb
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const SetupScreen()),
                            ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isFoc
                            ? Rs.accent.withValues(alpha: 0.15)
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isFoc ? Rs.accent : Colors.transparent,
                          width: 1.5,
                        ),
                        boxShadow: isFoc
                            ? [
                                BoxShadow(
                                    color: Rs.glow(0.25), blurRadius: 10)
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              kIsWeb
                                  ? Icons.logout_rounded
                                  : Icons.settings_ethernet_rounded,
                              color: isFoc ? Rs.accent : Colors.white70,
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                              kIsWeb
                                  ? 'Zugriff widerrufen'
                                  : 'Server neu konfigurieren',
                              style: TextStyle(
                                  color:
                                      isFoc ? Rs.accent : Colors.white70)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _disconnectWeb() async {
    await ref.read(authTokenProvider.notifier).clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebAccessScreen()),
      (route) => false,
    );
  }

  void _handleUpdateAction(UpdateState state) {
    switch (state) {
      case UpdateAvailable():
        ref.read(updateProvider.notifier).install(state.release);
      case UpdateError():
      case UpdateUpToDate():
      case UpdateIdle():
        ref.read(updateProvider.notifier).check();
      case UpdateChecking():
      case UpdateDownloading():
        break; // already in progress
    }
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _UpdateStatusChip extends StatelessWidget {
  final UpdateState state;
  const _UpdateStatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      UpdateIdle()        => ('Nicht geprüft', Colors.white24),
      UpdateChecking()    => ('Wird geprüft…', Colors.blue),
      UpdateUpToDate()    => ('Aktuell', Colors.green),
      UpdateAvailable(:final release)   => ('→ v${release.version}', Rs.accent),
      UpdateDownloading(:final release) => ('↓ v${release.version}', Rs.accent),
      UpdateError()       => ('Fehler', Colors.redAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Download progress bar ─────────────────────────────────────────────────────

class _DownloadProgress extends StatelessWidget {
  final double progress;
  const _DownloadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(Rs.accent),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(progress * 100).toStringAsFixed(0)} %',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Release notes ─────────────────────────────────────────────────────────────

class _ReleaseNotes extends StatelessWidget {
  final String body;
  const _ReleaseNotes({required this.body});

  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        body,
        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _UpdateButton extends StatefulWidget {
  final UpdateState state;
  final bool isFocused;
  final VoidCallback onPressed;
  const _UpdateButton({
    required this.state,
    required this.isFocused,
    required this.onPressed,
  });

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton> {
  bool _hovered = false;

  bool get _active => widget.isFocused || _hovered;
  bool get _busy => widget.state is UpdateChecking || widget.state is UpdateDownloading;

  String get _label => switch (widget.state) {
        UpdateAvailable()   => 'Jetzt aktualisieren',
        UpdateChecking()    => 'Wird geprüft…',
        UpdateDownloading() => 'Wird heruntergeladen…',
        _                   => 'Auf Updates prüfen',
      };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _busy ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: widget.state is UpdateAvailable
                ? (_active ? Rs.accentLight : Rs.accent)
                : (_active ? Rs.panel3 : Rs.panel2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _active ? Rs.accent : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54),
                )
              else
                Icon(
                  widget.state is UpdateAvailable
                      ? Icons.system_update_rounded
                      : Icons.refresh_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              const SizedBox(width: 8),
              Text(_label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Storage usage row ─────────────────────────────────────────────────────────

class _StorageUsageRow extends StatelessWidget {
  final StorageRoot root;
  final bool showLabel;
  const _StorageUsageRow({required this.root, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final hasDiskInfo = root.diskTotalBytes > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              showLabel ? root.label : 'Downloads',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(formatBytes(root.downloadsBytes),
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        if (hasDiskInfo) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: root.diskUsedFraction,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                root.diskUsedFraction > 0.9 ? Colors.redAccent : Rs.accent,
              ),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatBytes(root.diskFreeBytes)} frei von ${formatBytes(root.diskTotalBytes)} auf dem Server',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                color: Rs.accent,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Rs.panel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
