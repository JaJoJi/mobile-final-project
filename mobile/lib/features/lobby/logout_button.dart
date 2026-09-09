import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/widgets/app_modal.dart';

/// AppBar action that signs the user out and returns them to `/login`.
///
/// Always shows an `AppModal.confirm` first — accidental logouts are a
/// common UX failure on mobile, and the dialog also doubles as a
/// confirmation that the user's stored tokens are about to be cleared.
///
/// Side effects on confirm:
///   1. `AuthRepository.logout()` — wipes access/refresh/userId from
///      secure storage.
///   2. `AuthGate.signalSignedOut()` — flips the router's
///      `refreshListenable` so the redirect bounces them away from
///      any non-auth route they're currently on.
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout),
      onPressed: () => _confirmAndLogout(context, ref),
    );
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'Sign out?',
      message: "You'll have to sign in again to play.",
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed) return;

    final auth = ref.read(authRepositoryProvider);
    await auth.logout();
    AuthGate.instance.signalSignedOut();
    if (!context.mounted) return;
    context.go('/login');
  }
}
