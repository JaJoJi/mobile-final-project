import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'match_models.dart';

/// One row of the match-detail round table — design spec §4.7.
///
/// The spec's damage column needs per-round damage, which only exists once
/// the Round Orchestrator (P0-BE-13) writes it; until then this shows the
/// event count from the stored `events[]` instead.
class RoundRow extends StatelessWidget {
  const RoundRow({super.key, required this.round});

  final RoundSummary round;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final numStyle =
        AppTypography.tabular(t.textTheme.bodyLarge ?? const TextStyle());

    return Semantics(
      label: 'รอบ ${round.roundNumber} '
          '${round.winnerName != null ? 'ผู้ชนะ ${round.winnerName}' : ''} '
          '${round.eventCount} เหตุการณ์',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text('${round.roundNumber}', style: numStyle),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                round.winnerName ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '${round.eventCount} เหตุการณ์',
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
