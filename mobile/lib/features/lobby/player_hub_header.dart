import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_toast.dart';
import 'logout_button.dart';
import 'profile_card.dart';

/// Compact player identity header shared across Player Hub destinations.
class PlayerHubHeader extends StatelessWidget {
  const PlayerHubHeader({super.key});

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: Color(0x52071220),
            border: Border(
              bottom: BorderSide(color: Color(0x3359B7E8)),
            ),
          ),
          child: Row(
            children: [
              const Expanded(child: ProfileCard(embedded: true)),
              Container(
                width: 1,
                height: AppSpacing.xxl,
                color: const Color(0x406FA5C4),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: 'การแจ้งเตือน',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x4D102538),
                ),
                onPressed: () => AppToast.show(
                  context,
                  'ระบบแจ้งเตือนจะเปิดให้ใช้งานเร็ว ๆ นี้',
                ),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
              const LogoutButton(decorated: true),
            ],
          ),
        ),
      );
}
