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
  const LogoutButton({
    super.key,
    this.decorated = false,
    this.showLabel = false,
  });

  final bool decorated;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (showLabel) {
      return Tooltip(
        message: 'ออกจากระบบ',
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
            color: const Color(0xE6153044),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x4052738C)),
          ),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF4F7FF),
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            onPressed: () => _confirmAndLogout(context, ref),
            icon: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0x24FF8F9B),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                size: 17,
                color: Color(0xFFFF8F9B),
              ),
            ),
            label: const Text(
              'ออกจากระบบ',
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'ออกจากระบบ',
      style: decorated
          ? IconButton.styleFrom(
              backgroundColor: const Color(0x4D102538),
            )
          : null,
      icon: const Icon(Icons.logout),
      onPressed: () => _confirmAndLogout(context, ref),
    );
  }

  Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'ออกจากระบบ?',
      message: 'คุณต้องเข้าสู่ระบบใหม่เพื่อเล่นอีกครั้ง',
      confirmLabel: 'ออกจากระบบ',
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
