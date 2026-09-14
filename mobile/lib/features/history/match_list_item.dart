import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import 'history_format.dart';
import 'match_models.dart';

/// One row in `/history` — design spec §4.6.
///
/// Three redundant cues for the result **[MUST]**: a 4 dp status stripe,
/// an icon, and the word (ชนะ / แพ้ / เสมอ). Row is ≥ 72 dp so the whole
/// thing is a comfortable tap target.
class MatchListItem extends StatelessWidget {
  const MatchListItem({super.key, required this.entry, required this.onTap});

  final MatchHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;

    final (color, icon) = switch (entry.outcome) {
      MatchOutcome.win => (game.success, Icons.check_circle),
      MatchOutcome.loss => (t.colorScheme.error, Icons.cancel),
      MatchOutcome.tie => (t.colorScheme.onSurfaceVariant, Icons.remove_circle),
    };
    final word = outcomeWordThai(entry.outcome);
    final opponent = entry.opponentName ?? 'ผู้เล่นที่ลบบัญชี';

    return Semantics(
      button: true,
      label: '$word พบ $opponent ${entry.rounds} รอบ '
          '${relativeThai(entry.createdAt)}ที่แล้ว',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(
            children: [
              Container(width: 4, height: 48, color: color),
              const SizedBox(width: AppSpacing.md),
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 44,
                child: Text(word, style: t.textTheme.titleMedium),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'พบ $opponent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${entry.rounds} รอบ',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                relativeThai(entry.createdAt),
                style: t.textTheme.labelMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
