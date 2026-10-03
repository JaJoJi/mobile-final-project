import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/widgets.dart';
import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';
import '../lobby/profile_card.dart';
import 'history_format.dart';
import 'history_providers.dart';
import 'match_models.dart';
import 'round_row.dart';

/// `/history/:matchId` — the result and round winners for one past match.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(matchDetailProvider(matchId));
    final currentUserId =
        ref.watch(currentUserProvider).valueOrNull?['id'] as String?;

    return Theme(
      data: fantasySurfaceTheme(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const PlayerHubHeader(),
                const _DetailHeader(),
                Expanded(
                  child: detail.when(
                    loading: () => const _DetailSkeleton(),
                    error: (_, __) => Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: FantasyPanel(
                        translucent: true,
                        child: ErrorView(
                          message: 'โหลดรายละเอียดแมตช์ไม่ได้ ลองอีกครั้ง',
                          onRetry: () =>
                              ref.invalidate(matchDetailProvider(matchId)),
                        ),
                      ),
                    ),
                    data: (value) => _Detail(
                      detail: value,
                      currentUserId: currentUserId,
                    ),
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.history),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'กลับ',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/history');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFFFD35A),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รายละเอียดแมตช์',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFFF5D6),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    'ผลการแข่งขันในแต่ละรอบ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD7E8FF),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.detail, required this.currentUserId});

  final MatchDetail detail;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final names = detail.players.map((p) => p.name ?? 'ผู้เล่น').toList();
    final firstPlayer = names.isNotEmpty ? names.first : 'ผู้เล่น 1';
    final secondPlayer = names.length > 1 ? names[1] : 'ผู้เล่น 2';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _MatchResultCard(
          firstPlayer: firstPlayer,
          secondPlayer: secondPlayer,
          winnerId: detail.winnerId,
          winnerName: detail.winnerName,
          currentUserId: currentUserId,
          status: detail.status,
          createdAt: detail.createdAt,
          duration: detail.duration,
        ),
        const SizedBox(height: AppSpacing.lg),
        _RoundSectionHeader(roundCount: detail.rounds.length),
        const SizedBox(height: AppSpacing.sm),
        if (detail.rounds.isEmpty)
          const FantasyPanel(
            translucent: true,
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: Text('ยังไม่มีข้อมูลรอบสำหรับแมตช์นี้')),
          )
        else
          ...detail.rounds.map(
            (round) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: RoundRow(
                round: round,
                currentUserId: currentUserId,
              ),
            ),
          ),
      ],
    );
  }
}

class _MatchResultCard extends StatelessWidget {
  const _MatchResultCard({
    required this.firstPlayer,
    required this.secondPlayer,
    required this.winnerId,
    required this.winnerName,
    required this.currentUserId,
    required this.status,
    required this.createdAt,
    required this.duration,
  });

  final String firstPlayer;
  final String secondPlayer;
  final String? winnerId;
  final String? winnerName;
  final String? currentUserId;
  final String status;
  final DateTime createdAt;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final inProgress = status == 'in_progress';
    final didWin = winnerId != null && winnerId == currentUserId;
    final didLose =
        winnerId != null && currentUserId != null && winnerId != currentUserId;
    final resultColor = didWin
        ? game.success
        : didLose
            ? theme.colorScheme.error
            : const Color(0xFFB8CEF0);
    final resultText = inProgress
        ? 'กำลังแข่งขัน'
        : winnerName == null
            ? 'เสมอ'
            : didWin
                ? 'ชนะ'
                : didLose
                    ? 'แพ้ให้ $winnerName'
                    : '$winnerName ชนะ';
    final dateText = '${createdAt.day}/${createdAt.month}/'
        '${createdAt.year + 543} · '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';

    return FantasyPanel(
      translucent: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Container(
            width: AppSpacing.huge,
            height: AppSpacing.huge,
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: resultColor.withValues(alpha: 0.7)),
            ),
            child: Icon(
              inProgress
                  ? Icons.sports_martial_arts_rounded
                  : winnerName == null
                      ? Icons.handshake_outlined
                      : didLose
                          ? Icons.close_rounded
                          : Icons.emoji_events_rounded,
              color: resultColor,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            resultText,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: resultColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PlayerName(
                  name: firstPlayer,
                  alignment: Alignment.centerRight,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC07131F),
                    borderRadius: AppRadius.allFull,
                    border: Border.all(color: const Color(0x80FFD35A)),
                  ),
                  child: Text(
                    'VS',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFFFD35A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _PlayerName(
                  name: secondPlayer,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(
            duration == null
                ? dateText
                : '$dateText · ${formatDuration(duration!)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFB8CEF0),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.name, required this.alignment});

  final String name;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFF4F7FB),
                fontWeight: FontWeight.w800,
              ),
        ),
      );
}

class _RoundSectionHeader extends StatelessWidget {
  const _RoundSectionHeader({required this.roundCount});

  final int roundCount;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(
            Icons.format_list_numbered_rounded,
            size: 20,
            color: Color(0xFFFFD35A),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'ผลแต่ละรอบ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFFFF5D6),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Text(
            '$roundCount รอบ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFB8CEF0),
                ),
          ),
        ],
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          SkeletonBox(height: 220),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 24, width: 160),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 72),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 72),
        ],
      );
}
