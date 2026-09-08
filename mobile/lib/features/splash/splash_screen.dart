import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final auth = ref.read(authRepositoryProvider);

    var settled = false;
    void settle(bool signedIn) {
      if (settled) return;
      settled = true;
      signedIn
          ? AuthGate.instance.signalSignedIn()
          : AuthGate.instance.signalSignedOut();
      // Nudge the router in case the redirect didn't already fire.
      if (mounted) context.go(signedIn ? '/lobby' : '/login');
    }

    Future<void>.delayed(SplashScreen._maxWait).then((_) => settle(false));

    final hasToken = (await auth.getAccessToken())?.isNotEmpty ?? false;
    if (!hasToken) {
      settle(false);
      return;
    }
    final refreshed = await auth.tryRefresh();
    settle(refreshed != null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.castle, size: 72, color: t.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Auto Chess', style: t.textTheme.headlineMedium),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
