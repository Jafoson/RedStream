import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_service.dart';
import '../providers/providers.dart';
import '../theme/rs_theme.dart';
import '../widgets/rs_logo.dart';
import '../widgets/tv_keyboard_dialog.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool isSetup;
  const LoginScreen({super.key, this.isSetup = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _host = '';
  String _username = '';
  String _password = '';
  final _hostFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _btnFocus = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _host = ref.read(serverUrlProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hostFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hostFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _btnFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final host = _host.trim();
    final username = _username.trim();
    final password = _password;
    if (host.isEmpty) {
      setState(() => _error = 'Bitte Server-URL eingeben.');
      return;
    }
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte Benutzername und Passwort eingeben.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(serverUrlProvider.notifier).setUrl(host);
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
          builder: (_) =>
              hasProfile ? const HomeScreen() : const ProfileScreen(),
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
      body: Stack(
        children: [
          const Positioned(
            top: 24,
            right: 28,
            child: RsLogo(iconSize: 28, textSize: 20),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      widget.isSetup ? 'Admin-Konto erstellen' : 'Anmelden',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Rs.text),
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                widget.isSetup
                    ? 'Erstelle den ersten Admin-Account für RedStream.'
                    : 'Melde dich an, um fortzufahren.',
                style: const TextStyle(fontSize: 15, color: Rs.muted),
              ),
              const SizedBox(height: 32),

              // ── Server URL ───────────────────────────────────────────────
              _FieldLabel('Server-URL'),
              const SizedBox(height: 8),
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _userFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TvTextInput(
                  label: 'http://192.168.1.x:8080',
                  value: _host,
                  focusNode: _hostFocus,
                  onChanged: (v) => setState(() => _host = v),
                  onSubmitted: (_) => _userFocus.requestFocus(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Username ─────────────────────────────────────────────────
              _FieldLabel('Benutzername'),
              const SizedBox(height: 8),
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _passFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _hostFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TvTextInput(
                  label: 'Benutzername eingeben',
                  value: _username,
                  focusNode: _userFocus,
                  onChanged: (v) => setState(() => _username = v),
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Password ─────────────────────────────────────────────────
              _FieldLabel('Passwort'),
              const SizedBox(height: 8),
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _userFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _btnFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TvTextInput(
                  label: 'Passwort eingeben',
                  value: _password,
                  obscureText: true,
                  focusNode: _passFocus,
                  onChanged: (v) => setState(() => _password = v),
                  onSubmitted: (_) => _submit(),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 14))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // ── Submit button ────────────────────────────────────────────
              Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _passFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: _LoginButton(
                  label: widget.isSetup ? 'Konto erstellen' : 'Anmelden',
                  loading: _loading,
                  focusNode: _btnFocus,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
          ),
        ),
        ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Rs.muted,
          letterSpacing: 0.5));
}

class _LoginButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  const _LoginButton(
      {required this.label,
      required this.loading,
      required this.onPressed,
      this.focusNode});

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
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
            boxShadow: [
              BoxShadow(
                  color: Rs.accent.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(widget.label,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
