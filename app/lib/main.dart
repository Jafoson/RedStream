import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_service.dart';
import 'providers/providers.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';
import 'theme/rs_theme.dart';

enum _AppInitScreen { serverSetup, adminSetup, login, profileSelect, home }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString('server_url') ?? '';
  final activeProfileId = prefs.getInt('active_profile_id');
  final storedToken = prefs.getString('auth_token');

  final initScreen = await _resolveInitScreen(
    serverUrl: serverUrl,
    activeProfileId: activeProfileId,
    storedToken: storedToken,
    prefs: prefs,
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: _AniWorldApp(initScreen: initScreen),
    ),
  );
}

Future<_AppInitScreen> _resolveInitScreen({
  required String serverUrl,
  required int? activeProfileId,
  required String? storedToken,
  required SharedPreferences prefs,
}) async {
  if (serverUrl.isEmpty) return _AppInitScreen.serverSetup;

  try {
    final api = ApiService(serverUrl);
    final authStatus = await api.checkAuth();

    if (!authStatus.authEnabled) {
      return activeProfileId != null ? _AppInitScreen.home : _AppInitScreen.profileSelect;
    }
    if (authStatus.setupNeeded) {
      return _AppInitScreen.adminSetup;
    }
    if (storedToken == null || storedToken.isEmpty) {
      return _AppInitScreen.login;
    }
    // Validate stored token
    try {
      final authApi = ApiService(serverUrl, authToken: storedToken);
      await authApi.me();
      return activeProfileId != null ? _AppInitScreen.home : _AppInitScreen.profileSelect;
    } catch (_) {
      await prefs.remove('auth_token');
      return _AppInitScreen.login;
    }
  } catch (_) {
    // Backend unreachable — proceed without auth
    return activeProfileId != null ? _AppInitScreen.home : _AppInitScreen.profileSelect;
  }
}

class _AniWorldApp extends StatelessWidget {
  final _AppInitScreen initScreen;
  const _AniWorldApp({required this.initScreen});

  @override
  Widget build(BuildContext context) {
    final Widget home = switch (initScreen) {
      _AppInitScreen.serverSetup  => const SetupScreen(),
      _AppInitScreen.adminSetup   => const LoginScreen(isSetup: true),
      _AppInitScreen.login        => const LoginScreen(),
      _AppInitScreen.profileSelect => const ProfileScreen(),
      _AppInitScreen.home         => const HomeScreen(),
    };
    return MaterialApp(
      title: 'RedStream',
      debugShowCheckedModeBanner: false,
      theme: Rs.theme(),
      home: home,
    );
  }
}
