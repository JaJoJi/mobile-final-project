import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/settings_provider.dart';

/// App entry.
///
/// Routing + auth flow live in `core/router.dart`:
///   - launch → `/splash` resolves the session (token check + silent
///     refresh), then the router redirect lands the user on `/lobby` or
///     `/login`.
///   - a `401` mid-session auto-refreshes and retries once
///     (`core/api/api_client.dart`); a dead refresh token signs the user
///     out and the redirect returns them to `/login`.
///
/// Design tokens live in `core/theme` (design spec §2). The active
/// [ThemeMode] comes from `settingsProvider` (P1-FE-02, `/profile`); the
/// `/dev/gallery` widget catalogue is registered in `buildRouter()`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AutoChessApp(),
    ),
  );
}

class AutoChessApp extends ConsumerStatefulWidget {
  const AutoChessApp({super.key});

  @override
  ConsumerState<AutoChessApp> createState() => _AutoChessAppState();
}

class _AutoChessAppState extends ConsumerState<AutoChessApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider).themeMode;
    return MaterialApp.router(
      title: 'Auto Chess',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
