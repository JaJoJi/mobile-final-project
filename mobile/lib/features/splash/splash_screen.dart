import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/platform/bootstrap_overlay.dart';
import '../../core/widgets/game_art_frame.dart';
import '../history/history_providers.dart';
import '../lobby/profile_card.dart';
import '../player_hub/player_hub_fixture_provider.dart';
import 'launch_backdrop.dart';

/// Auth gate shown on launch (design spec §4.1).
///
/// Reads the stored access token; if present, does one silent refresh to
/// confirm the session is still good. Resolves [AuthGate] to `true` /
/// `false`, which makes the router leave this screen for `/lobby` or
/// `/login`. Falls back to signed-out after [_maxWait] so a slow network
/// can't hang the launch.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const path = '/splash';
  static const _maxWait = Duration(seconds: 3);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallback;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void dispose() {
    _fallback?.cancel();
    super.dispose();
  }

  Future<void> _settle(bool signedIn) async {
    if (_settled || !mounted) return;
    _settled = true;
    _fallback?.cancel();
    await _prepareDestination(signedIn);
    if (!mounted) return;
    signedIn
        ? AuthGate.instance.signalSignedIn()
        : AuthGate.instance.signalSignedOut();
    // Nudge the router in case the redirect didn't already fire.
    if (mounted) context.go(signedIn ? '/lobby' : '/login');
    // On web, keep the HTML bootstrap above this internal auth route until
    // the actual destination has painted. This prevents a second splash from
    // flashing between the browser bootstrap and Login / Lobby.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    hideBootstrapOverlay();
  }

  Future<void> _prepareDestination(bool signedIn) async {
    // Retain auto-dispose data until the destination takes over its listeners.
    // Do not signal auth-ready first: the router would immediately leave splash.
    if (signedIn) {
      ref.listenManual(currentUserProvider, (_, __) {});
      ref.listenManual(leaderboardSourceProvider, (_, __) {});
      ref.listenManual(matchHistoryProvider, (_, __) {});
    }
    final pending = <Future<Object?>>[
      precacheImage(
        const AssetImage(GameBackgroundAssets.arenaBlurred),
        context,
      ),
      precacheImage(const AssetImage(GameUiAssets.panelTextureBlue), context),
      if (signedIn) ...[
        precacheImage(
          const AssetImage(GameBackgroundAssets.homeTeamBanner),
          context,
        ),
        ref.read(currentUserProvider.future),
        ref.read(leaderboardSourceProvider.future),
        ref.read(matchHistoryProvider.future),
      ],
    ];
    try {
      // Secondary feed failures must not sign a valid user out or trap launch.
      await Future.wait(pending).timeout(const Duration(seconds: 3));
    } catch (_) {
      // The destination already has error / retry states for failed requests.
    }
  }

  Future<void> _resolve() async {
    final auth = ref.read(authRepositoryProvider);

    // Never hang the launch on a slow / dead network.
    _fallback = Timer(SplashScreen._maxWait, () => _settle(false));

    final hasToken = (await auth.getAccessToken())?.isNotEmpty ?? false;
    if (!hasToken) {
      await _settle(false);
      return;
    }
    final refreshed = await auth.tryRefresh();
    await _settle(refreshed != null);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF071624),
      body: LaunchBackdrop(),
    );
  }
}
