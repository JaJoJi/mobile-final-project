import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import 'match_models.dart';

/// A compact result card showing only the winner of one combat round.
class RoundRow extends StatelessWidget {
  const RoundRow({
    super.key,
    required this.round,
    required this.currentUserId,
  });

  final RoundSummary round;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final hasWinner = round.winnerName != null;
    final didWin = round.winnerId != null && round.winnerId == currentUserId;
    final didLose = round.winnerId != null &&
        currentUserId != null &&
        round.winnerId != currentUserId;
    final color = didWin
        ? game.success
        : didLose
            ? theme.colorScheme.error
            : const Color(0xFFB8CEF0);
    final result = hasWinner ? round.winnerName! : 'เสมอ';

    return Semantics(
      label:
          'รอบ ${round.roundNumber} ${hasWinner ? 'ผู้ชนะ $result' : result}',
      excludeSemantics: true,
      child: FantasyPanel(
        translucent: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: AppSpacing.huge,
              height: AppSpacing.huge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xCC07131F),
                borderRadius: AppRadius.allMd,
                border: Border.all(color: const Color(0x806FA5C4)),
              ),
              child: Text(
                '${round.roundNumber}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFFFD35A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รอบที่ ${round.roundNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB8CEF0),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hasWinner ? '$result ชนะ' : result,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              hasWinner ? Icons.emoji_events_rounded : Icons.handshake_outlined,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
