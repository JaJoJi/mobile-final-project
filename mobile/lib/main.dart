import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/dev/widget_gallery_screen.dart';
import 'features/health/health_screen.dart';

/// App entry. Auth-aware routing:
///   - First screen: LoginScreen
///   - Push to /register → RegisterScreen
///   - On successful login/register: push-replace to /home → HealthScreen
///
/// Tokens are persisted in flutter_secure_storage by AuthRepository, so
/// a returning user sees the home screen next launch (no logout
/// happens; tokens survive).
void main() {
  runApp(const ProviderScope(child: AutoChessApp()));
}

class AutoChessApp extends StatelessWidget {
  const AutoChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Chess',
      debugShowCheckedModeBanner: false,
      // Design tokens live in core/theme (design spec §2). Both themes are
      // defined now; the user-facing toggle ships with P1-FE-02.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      initialRoute: '/login',
      routes: {
        '/login': (ctx) => const LoginScreen(),
        '/register': (ctx) => const RegisterScreen(),
        '/home': (ctx) => const HealthScreen(),
        '/dev/gallery': (ctx) => const WidgetGalleryScreen(),
      },
    );
  }
}
