import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../widgets/tv_focusable.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

/// First-launch screen — user enters the backend server URL.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(serverUrlProvider);
    _controller = TextEditingController(
      text: existing.isNotEmpty ? existing : 'http://',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      setState(() => _error = 'Please enter a valid URL (http:// or https://)');
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
            builder: (_) => profileId != null ? const HomeScreen() : const ProfileScreen(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Cannot connect to server. Check the URL and try again.';
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
                Row(
                  children: [
                    Image.asset('assets/logo.png', width: 52, height: 52),
                    const SizedBox(width: 14),
                    Text('RedStream', style: tt.displayMedium?.copyWith(color: cs.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Enter your server URL to connect.', style: tt.bodyLarge),
                const SizedBox(height: 40),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  style: tt.bodyLarge,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.100:8080',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error, fontSize: 15)),
                ],
                const SizedBox(height: 32),
                TvFocusable(
                  onActivate: _saving ? null : _save,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            'Connect',
                            style: tt.labelLarge?.copyWith(color: Colors.black, fontSize: 18),
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
