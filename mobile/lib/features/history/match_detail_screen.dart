import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/widgets.dart';
import 'history_format.dart';
import 'history_providers.dart';
import 'match_models.dart';
import 'round_row.dart';

/// `/history/:matchId` — round-by-round detail (design spec §4.7).
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(matchDetailProvider(matchId));

    return AppScaffold(
      title: 'รายละเอียดแมตช์',
      body: detail.when(
        loading: () => const _DetailSkeleton(),
        error: (_, __) => ErrorView(
          message: 'โหลดรายละเอียดแมตช์ไม่ได้ ลองอีกครั้ง',
          onRetry: () => ref.invalidate(matchDetailProvider(matchId)),
        ),
        data: (d) => SingleChildScrollView(child: _Detail(detail: d)),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;

    final names = detail.players.map((p) => p.name ?? 'ผู้เล่น').toList();
    final matchup = names.length == 2 ? '${names[0]} พบ ${names[1]}' : 'แมตช์';

    final outcome = detail.status == 'in_progress'
        ? null
        : detail.winnerName; // null winner ⇒ tie / no result
    final (chipColor, chipText) = switch (detail.status) {
      'in_progress' => (t.colorScheme.onSurfaceVariant, 'กำลังแข่ง'),
      _ when outcome == null => (t.colorScheme.onSurfaceVariant, 'เสมอ'),
      _ => (game.success, 'ผู้ชนะ: $outcome'),
    };

    final when = detail.createdAt;
    final subtitle =
        StringBuffer('${when.day}/${when.month}/${when.year + 543} · '
            '${when.hour.toString().padLeft(2, '0')}:'
            '${when.minute.toString().padLeft(2, '0')}');
    if (detail.duration != null) {
      subtitle.write(' · ${formatDuration(detail.duration!)}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(matchup, style: t.textTheme.titleLarge)),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.allXs,
              ),
              child: Text(
                chipText,
                style: t.textTheme.labelMedium?.copyWith(color: chipColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle.toString(),
          style: t.textTheme.labelMedium
              ?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const Divider(height: AppSpacing.xl),
        Row(
          children: [
            SizedBox(
              width: 40,
              child: Text('รอบ', style: t.textTheme.titleMedium),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('ผู้ชนะรอบ', style: t.textTheme.titleMedium),
            ),
            Text('เหตุการณ์', style: t.textTheme.titleMedium),
          ],
        ),
        if (detail.rounds.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Text(
              'ยังไม่มีข้อมูลรอบสำหรับแมตช์นี้',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final r in detail.rounds) ...[
            const Divider(height: 1),
            RoundRow(round: r),
          ],
      ],
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 28, width: 220),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 160),
          SizedBox(height: AppSpacing.xl),
          SkeletonBox(height: 40),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 40),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 40),
        ],
      ),
    );
  }
}
