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
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return AppCard(
      child: userAsync.when(
        data: (user) => _ProfileContent(
          username: user['username'] as String? ?? 'unknown',
          rating: user['rating'] as int? ?? 0,
        ),
        loading: () => const _ProfileSkeleton(),
        error: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'Couldn\u2019t load profile',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.username, required this.rating});

  final String username;
  final int rating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initialsFor(username);

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(
            initials,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: Theme.of(context).textTheme.titleLarge,
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
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'rating: $rating',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
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
              SkeletonBox(width: 80, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}
