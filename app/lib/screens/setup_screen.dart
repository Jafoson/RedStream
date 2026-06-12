import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_keyboard_dialog.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  String _protocol = 'http://';
  String _host = '';

  final _httpFocus = FocusNode();
  final _httpsFocus = FocusNode();
  final _urlFocus = FocusNode();
  final _btnFocus = FocusNode();

  bool _saving = false;
  String? _error;

  String get _fullUrl => '$_protocol$_host';

  @override
  void initState() {
    super.initState();
    final existing = ref.read(serverUrlProvider);
    if (existing.startsWith('https://')) {
      _protocol = 'https://';
      _host = existing.substring('https://'.length);
    } else if (existing.startsWith('http://')) {
      _protocol = 'http://';
      _host = existing.substring('http://'.length);
    } else {
      _host = existing;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _httpFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _httpFocus.dispose();
    _httpsFocus.dispose();
    _urlFocus.dispose();
    _btnFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _fullUrl.trim();
    if (_host.trim().isEmpty) {
      setState(() => _error = 'Bitte Host eingeben (z.B. 192.168.1.100:8080)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ApiService(url);
      final authStatus = await api.checkAuth();
      await ref.read(serverUrlProvider.notifier).setUrl(url);
      if (!mounted) return;
      if (authStatus.setupNeeded) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen(isSetup: true)),
        );
      } else if (authStatus.authEnabled) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        final profileId = ref.read(activeProfileIdProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                profileId != null ? const HomeScreen() : const ProfileScreen(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Keine Verbindung. URL und Server prüfen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RedStream',
                    style: tt.displayMedium?.copyWith(color: cs.primary)),
                const SizedBox(height: 8),
                Text('Serveradresse eingeben.', style: tt.bodyLarge),
                const SizedBox(height: 40),

                // ── Protocol selector ──────────────────────────────────────
                Text('Protokoll',
                    style: tt.bodySmall
                        ?.copyWith(color: Rs.muted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ProtoChip(
                      label: 'http://',
                      selected: _protocol == 'http://',
                      focusNode: _httpFocus,
                      onSelect: () => setState(() => _protocol = 'http://'),
                      onRight: () => _httpsFocus.requestFocus(),
                      onDown: () => _urlFocus.requestFocus(),
                    ),
                    const SizedBox(width: 10),
                    _ProtoChip(
                      label: 'https://',
                      selected: _protocol == 'https://',
                      focusNode: _httpsFocus,
                      onSelect: () => setState(() => _protocol = 'https://'),
                      onLeft: () => _httpFocus.requestFocus(),
                      onDown: () => _urlFocus.requestFocus(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Host input ─────────────────────────────────────────────
                Text('Host : Port',
                    style: tt.bodySmall
                        ?.copyWith(color: Rs.muted, letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _httpFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _btnFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TvTextInput(
                    label: '192.168.1.100:8080',
                    value: _host,
                    focusNode: _urlFocus,
                    onChanged: (v) => setState(() => _host = v),
                  ),
                ),

                // Preview
                if (_host.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _fullUrl,
                      style: const TextStyle(color: Rs.muted, fontSize: 13),
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: cs.error.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: cs.error, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                                color: cs.error, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Connect button ─────────────────────────────────────────
                // Outer Focus catches arrowUp that TvFocusable ignores
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _urlFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TvFocusable(
                    focusNode: _btnFocus,
                    onActivate: _saving ? null : _save,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              'Verbinden',
                              style: tt.labelLarge?.copyWith(
                                  color: Colors.black, fontSize: 18),
                            ),
                    ),
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

class _ProtoChip extends StatefulWidget {
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onDown;

  const _ProtoChip({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onSelect,
    this.onLeft,
    this.onRight,
    this.onDown,
  });

  @override
  State<_ProtoChip> createState() => _ProtoChipState();
}

class _ProtoChipState extends State<_ProtoChip> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.gameButtonA) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
          widget.onLeft!();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight && widget.onRight != null) {
          widget.onRight!();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && widget.onDown != null) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: widget.selected
                ? Rs.accent
                : _focused
                    ? Rs.panel2
                    : Rs.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? Rs.accentLight : Rs.line,
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused
                ? [BoxShadow(color: Rs.glow(0.3), blurRadius: 12)]
                : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected || _focused ? Colors.white : Rs.muted,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
