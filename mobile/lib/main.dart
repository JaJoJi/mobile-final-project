import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';

/// App entry.
///
/// Routing + auth flow live in `core/router.dart`:
///   - launch → `/splash` resolves the session (token check + silent
///     refresh), then the router redirect lands the user on `/lobby` or
///     `/login`.
///   - a `401` mid-session auto-refreshes and retries once
///     (`core/api/api_client.dart`); a dead refresh token signs the user
///     out and the redirect returns them to `/login`.
void main() {
  runApp(const ProviderScope(child: AutoChessApp()));
}

class AutoChessApp extends StatefulWidget {
  const AutoChessApp({super.key});

  @override
  State<AutoChessApp> createState() => _AutoChessAppState();
}

class _AutoChessAppState extends State<AutoChessApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Auto Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
