import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_logo.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// Shown only on the Flutter *web* build. There is no username/password
/// form here — a browser without a valid token asks the backend for access,
/// and an admin has to approve it from the server terminal
/// (`aniworld --web-requests` / `--web-approve <id>`). This screen just
/// polls until that happens.
class WebAccessScreen extends ConsumerStatefulWidget {
  const WebAccessScreen({super.key});

  @override
  ConsumerState<WebAccessScreen> createState() => _WebAccessScreenState();
}

enum _WebAccessState { requesting, pending, denied, error }

class _WebAccessScreenState extends ConsumerState<WebAccessScreen> {
  static const _deviceIdKey = 'web_device_id';

  _WebAccessState _state = _WebAccessState.requesting;
  Timer? _poll;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  ApiService get _api => ApiService(ref.read(serverUrlProvider));

  Future<void> _start() async {
    final prefs = ref.read(sharedPreferencesProvider);
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      try {
        deviceId = await _api.requestWebAccess();
        await prefs.setString(_deviceIdKey, deviceId);
      } catch (_) {
        if (mounted) setState(() => _state = _WebAccessState.error);
        return;
      }
    }
    _deviceId = deviceId;
    if (mounted) setState(() => _state = _WebAccessState.pending);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_deviceId == null) return;
    try {
      final result = await _api.pollWebAccess(_deviceId!);
      if (!mounted) return;
      switch (result.status) {
        case 'approved':
          if (result.token != null) await _onApproved(result.token!);
        case 'denied':
        case 'revoked':
          _poll?.cancel();
          await ref.read(sharedPreferencesProvider).remove(_deviceIdKey);
          setState(() => _state = _WebAccessState.denied);
      }
    } catch (_) {
      // Transient network error while polling — keep trying.
    }
  }

  Future<void> _onApproved(String token) async {
    _poll?.cancel();
    await ref.read(sharedPreferencesProvider).remove(_deviceIdKey);
    await ref.read(authTokenProvider.notifier).setToken(token);
    if (!mounted) return;
    final hasProfile = ref.read(activeProfileIdProvider) != null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => hasProfile ? const HomeScreen() : const ProfileScreen(),
      ),
    );
  }

  void _retry() {
    setState(() => _state = _WebAccessState.requesting);
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rs.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RsLogo(iconSize: 36, textSize: 28),
                const SizedBox(height: 40),
                _content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (_state) {
      case _WebAccessState.requesting:
        return const CircularProgressIndicator(color: Rs.accent);
      case _WebAccessState.pending:
        return Column(
          children: [
            const CircularProgressIndicator(color: Rs.accent),
            const SizedBox(height: 24),
            const Text(
              'Zugriff angefragt',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Rs.text),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ein Administrator muss diesen Browser auf dem Server freigeben, '
              'bevor es weitergeht.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Rs.muted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Rs.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Rs.line),
              ),
              child: const Text(
                'aniworld --web-requests\naniworld --web-approve <ID>',
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: Rs.text),
              ),
            ),
          ],
        );
      case _WebAccessState.denied:
        return Column(
          children: [
            const Icon(Icons.block, color: Colors.redAccent, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Zugriff verweigert',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Rs.text),
            ),
            const SizedBox(height: 12),
            const Text(
              'Der Administrator hat diese Anfrage abgelehnt oder widerrufen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Rs.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _retry, child: const Text('Erneut anfragen')),
          ],
        );
      case _WebAccessState.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Verbindungsfehler',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: Rs.text),
            ),
            const SizedBox(height: 12),
            const Text(
              'Der Server konnte nicht erreicht werden.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Rs.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _retry, child: const Text('Erneut versuchen')),
          ],
        );
    }
  }
}
