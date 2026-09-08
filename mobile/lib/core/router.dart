import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/dev/widget_gallery_screen.dart';
import '../features/history/history_list_screen.dart';
import '../features/history/match_detail_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/match/match_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/splash/splash_screen.dart';
import 'auth/auth_gate.dart';

/// App routing — single source of truth for navigation.
///
/// The redirect guard uses [AuthGate.instance.isSignedIn]:
///   * `null`  — auth not resolved yet → everything funnels to `/splash`,
///     which resolves it (token check + silent refresh) then leaves.
///   * `false` — not signed in → any non-auth route → `/login`.
///   * `true`  — signed in → `/login` `/register` `/splash` → `/lobby`.
///
/// `refreshListenable: AuthGate.instance` re-runs the redirect whenever the
/// interceptor signals a sign-out (expired refresh token), bouncing the
/// user to `/login` from wherever they were.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: SplashScreen.path,
    refreshListenable: AuthGate.instance,
    redirect: (context, state) {
      final signedIn = AuthGate.instance.isSignedIn;
      final loc = state.matchedLocation;
      const authRoutes = {LoginScreen.path, RegisterScreen.path};

      // Dev-only routes are never guarded.
      if (loc.startsWith('/dev/')) return null;

      if (signedIn == null) {
        return loc == SplashScreen.path ? null : SplashScreen.path;
      }
      if (!signedIn) {
        return authRoutes.contains(loc) ? null : LoginScreen.path;
      }
      if (authRoutes.contains(loc) || loc == SplashScreen.path) {
        return LobbyScreen.path;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: SplashScreen.path,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: LoginScreen.path,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: RegisterScreen.path,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: LobbyScreen.path,
        builder: (_, __) => const LobbyScreen(),
      ),
      GoRoute(
        path: '/match/:id',
        builder: (_, state) =>
            MatchScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: HistoryListScreen.path,
        builder: (_, __) => const HistoryListScreen(),
      ),
      GoRoute(
        path: '/history/:matchId',
        builder: (_, state) =>
            MatchDetailScreen(matchId: state.pathParameters['matchId']!),
      ),
      GoRoute(
        path: ProfileScreen.path,
        builder: (_, __) => const ProfileScreen(),
      ),
      // Dev tool: the P0-FE-06 widget catalogue. Not part of any user flow.
      GoRoute(
        path: '/dev/gallery',
        builder: (_, __) => const WidgetGalleryScreen(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('ไม่พบหน้านี้: ${state.uri}')),
    ),
  );
}
