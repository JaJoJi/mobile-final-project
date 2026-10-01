import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/platform/bootstrap_overlay.dart';
import '../../core/theme/app_spacing.dart';

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

  void _settle(bool signedIn) {
    if (_settled) return;
    _settled = true;
    _fallback?.cancel();
    signedIn
        ? AuthGate.instance.signalSignedIn()
        : AuthGate.instance.signalSignedOut();
    // Nudge the router in case the redirect didn't already fire.
    if (mounted) context.go(signedIn ? '/lobby' : '/login');
    // On web, keep the HTML bootstrap above this internal auth route until
    // the actual destination has painted. This prevents a second splash from
    // flashing between the browser bootstrap and Login / Lobby.
    WidgetsBinding.instance.addPostFrameCallback((_) => hideBootstrapOverlay());
  }

  Future<void> _resolve() async {
    final auth = ref.read(authRepositoryProvider);

    // Never hang the launch on a slow / dead network.
    _fallback = Timer(SplashScreen._maxWait, () => _settle(false));

    final hasToken = (await auth.getAccessToken())?.isNotEmpty ?? false;
    if (!hasToken) {
      _settle(false);
      return;
    }
    final refreshed = await auth.tryRefresh();
    _settle(refreshed != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071624),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.15,
            colors: [Color(0xFF183E58), Color(0xFF071624)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xE60D2639),
                  borderRadius: AppRadius.allLg,
                  border: Border.all(color: const Color(0xB359B7E8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 54,
                  color: Color(0xFFFFD35A),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'เตรียมเข้าสู่สนาม',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF77D8FF),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'ออโต้เชส',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: const Color(0xFFFFF5D6),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF77D8FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
