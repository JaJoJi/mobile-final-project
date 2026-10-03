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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: const Color(0x70102538),
              borderRadius: AppRadius.allLg,
              border: Border.all(color: const Color(0x406FA5C4)),
            ),
            child: Row(
              children: [
                const Expanded(child: ProfileCard(embedded: true)),
                Container(
                  width: 1,
                  height: AppSpacing.xxl,
                  color: const Color(0x406FA5C4),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'การแจ้งเตือน',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x66101F31),
                    side: const BorderSide(color: Color(0x406FA5C4)),
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
        ),
      );
}
