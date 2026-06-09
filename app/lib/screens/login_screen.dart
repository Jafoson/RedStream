import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool isSetup;
  const LoginScreen({super.key, this.isSetup = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte Benutzername und Passwort eingeben.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final serverUrl = ref.read(serverUrlProvider);
      final api = ApiService(serverUrl);
      final Map<String, String> result;
      if (widget.isSetup) {
        result = await api.setupAdmin(username, password);
      } else {
        result = await api.login(username, password);
      }
      final token = result['token']!;
      await ref.read(authTokenProvider.notifier).setToken(token);
      if (!mounted) return;
      final hasProfile = ref.read(activeProfileIdProvider) != null;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => hasProfile ? const HomeScreen() : const ProfileScreen(),
        ),
      );
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['error'] as String?;
      setState(() => _error = msg ?? 'Anmeldung fehlgeschlagen.');
    } catch (e) {
      setState(() => _error = 'Verbindungsfehler: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Rs.bg,
      body: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Rs.accent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Rs.accent.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  RichText(
                    text: const TextSpan(children: [
                      TextSpan(text: 'Red', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Rs.text, letterSpacing: -0.5)),
                      TextSpan(text: 'Stream', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Rs.accent, letterSpacing: -0.5)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Text(
                widget.isSetup ? 'Admin-Konto erstellen' : 'Anmelden',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Rs.text),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isSetup
                    ? 'Erstelle den ersten Admin-Account für RedStream.'
                    : 'Melde dich an, um fortzufahren.',
                style: const TextStyle(fontSize: 15, color: Rs.muted),
              ),
              const SizedBox(height: 32),
              // Username field
              _FieldLabel('Benutzername'),
              const SizedBox(height: 8),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _passFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _userCtrl,
                  focusNode: _userFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Rs.text, fontSize: 17),
                  decoration: _inputDeco('Benutzername eingeben'),
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
              ),
              const SizedBox(height: 20),
              // Password field
              _FieldLabel('Passwort'),
              const SizedBox(height: 8),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _userFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Rs.text, fontSize: 17),
                  decoration: _inputDeco('Passwort eingeben').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Rs.muted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              // Submit button
              _LoginButton(
                label: widget.isSetup ? 'Konto erstellen' : 'Anmelden',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Rs.muted2),
    filled: true,
    fillColor: Rs.panel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Rs.line)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Rs.line)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Rs.accent, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Rs.muted, letterSpacing: 0.5));
}

class _LoginButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  const _LoginButton({required this.label, required this.loading, required this.onPressed});

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _focused ? Rs.accentLight : Rs.accent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Rs.accent.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
