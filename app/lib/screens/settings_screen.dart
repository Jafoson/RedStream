import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'setup_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    await ref.read(serverUrlProvider.notifier).setUrl(_urlController.text);
    if (mounted) setState(() => _saved = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _saved = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final currentUrl = ref.watch(serverUrlProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      children: [
        Text('Settings', style: tt.displayMedium),
        const SizedBox(height: 40),

        // ── Server URL ──────────────────────────────────────────────────
        _Section(
          title: 'Server',
          children: [
            _SettingRow(
              label: 'Server URL',
              subtitle: currentUrl.isNotEmpty ? currentUrl : 'Not configured',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: tt.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: 'http://192.168.1.100:8080',
                          prefixIcon: Icon(Icons.dns_outlined),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _saveUrl(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TvFocusable(
                      autofocus: true,
                      onActivate: _saveUrl,
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: _saved ? Colors.green : cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _saved ? '✓ Saved' : 'Save',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // ── About ───────────────────────────────────────────────────────
        _Section(
          title: 'About',
          children: [
            _SettingRow(
              label: 'AniWorld TV',
              subtitle: 'Android TV client for AniWorld-Downloader',
              child: const Text('v1.0.0', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // ── Reconnect / reset ───────────────────────────────────────────
        _Section(
          title: 'Connection',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TvFocusable(
                onActivate: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_ethernet_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 8),
                      Text('Reconfigure server', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
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
            style: const TextStyle(fontSize: 12, letterSpacing: 1.2, color: Color(0xFF4FC3F7))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;
  const _SettingRow({required this.label, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.bodyLarge),
                    if (subtitle != null)
                      Text(subtitle!, style: tt.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
