import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/auth_gate.dart';
import 'core/error_logger.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'core/ws/ws_providers.dart';
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
///
/// The WebSocket gateway (`/game`) lifecycle is driven from here too:
///   * `AuthGate` flips to signed-in → `_AutoChessAppState._onAuthChanged`
///     opens the WS connection so the lobby's `matchmakingStateProvider`
///     can actually `emit('game:matchmaking:join', ...)` once the user
///     taps Find match.
///   * `AuthGate` flips to signed-out (logout, expired refresh) → WS is
///     torn down so we don't leak the socket or waste reconnection
///     cycles against an unauthenticated session.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorLogger.init();
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
  bool? _lastSignedIn;

  @override
  void initState() {
    super.initState();
    // React to every subsequent auth flip (login, register, logout,
    // expired refresh). Cleaned up in `dispose` so the listener
    // doesn't outlive the widget tree on hot restart.
    AuthGate.instance.addListener(_onAuthChanged);
    // Pick up the splash screen's resolution when this widget mounts —
    // addListener fires for the initial assignment too.
  }

  @override
  void dispose() {
    AuthGate.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

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

  /// Connect / disconnect the WS client on auth transitions.
  ///
  /// Idempotent: caches the last signed-in state and only acts on real
  /// transitions (same value twice = no-op).
  void _onAuthChanged() {
    final signedIn = AuthGate.instance.isSignedIn ?? false;
    if (signedIn == _lastSignedIn) return;
    _lastSignedIn = signedIn;

    final client = ref.read(wsClientProvider);
    if (signedIn) {
      client.connect();
    } else {
      client.disconnect();
    }
  }
}
