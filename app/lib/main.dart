import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/providers.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'theme/rs_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString('server_url') ?? '';

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: AniWorldApp(hasServerUrl: serverUrl.isNotEmpty),
    ),
  );
}

class AniWorldApp extends StatelessWidget {
  final bool hasServerUrl;
  const AniWorldApp({super.key, required this.hasServerUrl});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedStream',
      debugShowCheckedModeBanner: false,
      theme: Rs.theme(),
      home: hasServerUrl ? const HomeScreen() : const SetupScreen(),
    );
  }
}
