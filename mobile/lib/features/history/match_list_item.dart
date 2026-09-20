import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import 'history_format.dart';
import 'match_models.dart';

/// A readable fantasy result card with redundant colour, icon and text cues.
class MatchListItem extends StatelessWidget {
  const MatchListItem({super.key, required this.entry, required this.onTap});

  final MatchHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final (color, icon) = switch (entry.outcome) {
      MatchOutcome.win => (game.success, Icons.emoji_events_outlined),
      MatchOutcome.loss => (theme.colorScheme.error, Icons.close_rounded),
      MatchOutcome.tie => (
          theme.colorScheme.onSurfaceVariant,
          Icons.remove_rounded,
        ),
    };
    final word = outcomeWordThai(entry.outcome);
    final opponent = entry.opponentName ?? 'ผู้เล่นที่ลบบัญชี';

    return Semantics(
      button: true,
      label: '$word พบ $opponent ${entry.rounds} รอบ '
          '${relativeThai(entry.createdAt)}ที่แล้ว',
      child: FantasyPanel(
        translucent: true,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.huge,
                    height: AppSpacing.huge,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: AppRadius.allMd,
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          word,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'พบ $opponent',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${entry.rounds} รอบ',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        relativeThai(entry.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
