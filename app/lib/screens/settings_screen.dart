import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_nav.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../utils/tv_keyboard.dart';
import 'setup_screen.dart';

// Nav rows: 0 = URL field, 1 = Save button, 2 = Reconfigure button
class SettingsScreen extends ConsumerStatefulWidget {
  final AppNavController nav;
  const SettingsScreen({super.key, required this.nav});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  final _urlFocus = FocusNode(skipTraversal: true);
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(serverUrlProvider));
    _urlFocus.addListener(_onUrlFocusChange);
    _urlFocus.showKeyboardOnFocus();
  }

  @override
  void dispose() {
    widget.nav.textInputActive = false;
    _urlFocus.removeListener(_onUrlFocusChange);
    _urlFocus.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onUrlFocusChange() {
    widget.nav.textInputActive = _urlFocus.hasFocus;
  }

  Future<void> _saveUrl() async {
    _urlFocus.unfocus();
    await ref.read(serverUrlProvider.notifier).setUrl(_urlController.text);
    if (mounted) setState(() => _saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final currentUrl = ref.watch(serverUrlProvider);

    // Nav: row 0 = URL field, row 1 = Save, row 2 = Reconfigure
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.nav.registerNav([1, 1, 1], (row, col) {
        switch (row) {
          case 0:
            _urlFocus.requestFocus();
          case 1:
            _saveUrl();
          case 2:
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const SetupScreen()),
            );
        }
      });
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      children: [
        Text('Settings', style: tt.displayMedium),
        const SizedBox(height: 40),

        // ── Server URL ──────────────────────────────────────────────────
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
                  // URL text field (nav row 0)
                  ListenableBuilder(
                    listenable: widget.nav,
                    builder: (_, _) {
                      final navFocused = widget.nav.isItemFocused(0, 0);
                      return TextField(
                        controller: _urlController,
                        focusNode: _urlFocus,
                        style: tt.bodyLarge,
                        onSubmitted: (_) => _saveUrl(),
                        decoration: InputDecoration(
                          hintText: 'http://192.168.1.100:8080',
                          prefixIcon: Icon(
                            Icons.dns_outlined,
                            color: navFocused ? Rs.accent : Rs.muted,
                          ),
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: navFocused ? Rs.accent : Rs.line2,
                              width: navFocused ? 2 : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Rs.accent, width: 2),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Rs.line2),
                          ),
                          filled: true,
                          fillColor: Rs.panel2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Save button (nav row 1)
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
                            _saved ? '✓ Saved' : 'Save',
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

        // ── About ───────────────────────────────────────────────────────
        _Section(
          title: 'About',
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AniWorld TV', style: tt.bodyLarge),
                        Text('Android TV client for AniWorld-Downloader',
                            style: tt.bodyMedium),
                      ],
                    ),
                  ),
                  const Text('v1.0.0',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // ── Connection ──────────────────────────────────────────────────
        _Section(
          title: 'Connection',
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ListenableBuilder(
                listenable: widget.nav,
                builder: (_, _) {
                  final isFoc = widget.nav.isItemFocused(2, 0);
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pushReplacement(
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
                          Icon(Icons.settings_ethernet_rounded,
                              color: isFoc ? Rs.accent : Colors.white70,
                              size: 20),
                          const SizedBox(width: 8),
                          Text('Reconfigure server',
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
}

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
