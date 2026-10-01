import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_toast.dart';
import 'logout_button.dart';
import 'profile_card.dart';

/// Compact player identity header shared across Player Hub destinations.
class PlayerHubHeader extends StatelessWidget {
  const PlayerHubHeader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Expanded(child: ProfileCard(embedded: true)),
            IconButton(
              tooltip: 'การแจ้งเตือน',
              onPressed: () => AppToast.show(
                context,
                'ระบบแจ้งเตือนจะเปิดให้ใช้งานเร็ว ๆ นี้',
              ),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            const LogoutButton(),
          ],
        ),
      );
}
