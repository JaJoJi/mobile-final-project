import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';

/// Fetches `/user/me` once when the lobby mounts and shows
/// `username` + `rating`.
///
/// Shows a `SkeletonBox` while the fetch is in flight (the parent
/// `AppScaffold` already handles connection state) — never a generic
/// spinner, per design spec §3.10.
final currentUserProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.getMe();
});

/// Profile card. Reads [currentUserProvider]; renders nothing useful while
/// the fetch is pending (just a skeleton of the same shape).
class ProfileCard extends ConsumerWidget {
  const ProfileCard({super.key, this.embedded = false});

  /// Omits the card surface when this content lives in a larger page header.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    final content = userAsync.when(
      data: (user) => _ProfileContent(
        username: user['username'] as String? ?? 'unknown',
        rating: user['rating'] as int? ?? 0,
        compact: embedded,
      ),
      loading: () => const _ProfileSkeleton(),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'โหลดข้อมูลผู้เล่นไม่สำเร็จ',
          style: TextStyle(color: Colors.red),
        ),
      ),
    );
    return embedded ? content : AppCard(child: content);
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.username,
    required this.rating,
    required this.compact,
  });

  final String username;
  final int rating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initialsFor(username);

    return Row(
      children: [
        CircleAvatar(
          radius: compact ? 24 : 28,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: compact ? 18 : 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: (compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x26FFD35A), Color(0xE617243A)],
                  ),
                  borderRadius: AppRadius.allFull,
                  border: Border.all(color: const Color(0x80FFD35A)),
                ),
                child: Semantics(
                  label: 'เรตติ้ง ${_formatRating(rating)}',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.military_tech_rounded,
                        size: 17,
                        color: Color(0xFFFFD35A),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _formatRating(rating),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: const Color(0xFFFFD35A),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initialsFor(String username) {
    final cleaned = username.trim();
    if (cleaned.isEmpty) return '?';
    // Take the first 1-2 characters as initials, upper-cased.
    if (cleaned.length == 1) return cleaned.toUpperCase();
    return cleaned.substring(0, 2).toUpperCase();
  }

  static String _formatRating(int rating) => rating.toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+$)'),
        (_) => ',',
      );
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    // Mirror the _ProfileContent shape so the card doesn't visibly resize
    // when the data arrives.
    return const Row(
      children: [
        SkeletonBox(width: 56, height: 56, radius: 28),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 120, height: 18),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(width: 72, height: 28, radius: AppRadius.full),
            ],
          ),
        ),
      ],
    );
  }
}
