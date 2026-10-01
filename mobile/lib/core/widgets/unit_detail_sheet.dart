import 'package:flutter/material.dart';

import '../../shared/models/unit.dart';
import '../../shared/models/unit_catalog.dart';
import '../theme/app_spacing.dart';
import '../utils/unit_star_level.dart';
import 'health_bar.dart';
import 'unit_avatar.dart';

void showUnitDetailSheet(
  BuildContext context, {
  required UnitId unitId,
  required int star,
  int? hp,
  int? maxHp,
  bool selectableTiers = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => UnitDetailSheet(
      unitId: unitId,
      star: star,
      hp: hp,
      maxHp: maxHp,
      selectableTiers: selectableTiers,
    ),
  );
}

/// The same unit detail is used by the match board and the unit catalog.
/// [hp] and [maxHp] describe a live match unit and are omitted in the catalog.
class UnitDetailSheet extends StatefulWidget {
  const UnitDetailSheet({
    super.key,
    required this.unitId,
    required this.star,
    this.hp,
    this.maxHp,
    this.selectableTiers = false,
  }) : assert(star >= 0 && star <= 2);

  final UnitId unitId;
  final int star;
  final int? hp;
  final int? maxHp;
  final bool selectableTiers;

  @override
  State<UnitDetailSheet> createState() => _UnitDetailSheetState();
}

class _UnitDetailSheetState extends State<UnitDetailSheet> {
  late int _tier = widget.star;

  @override
  void didUpdateWidget(covariant UnitDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.star != widget.star || oldWidget.unitId != widget.unitId) {
      _tier = widget.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = UnitCatalogEntry.of(widget.unitId);
    final displayStar = displayStarLevel(_tier);
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UnitAvatar(
                      unitId: widget.unitId.toJson(),
                      star: _tier,
                      size: UnitAvatarSize.sm,
                      variant: UnitAvatarVariant.bench,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text('$displayStar ดาว · ${info.role}'),
                        ],
                      ),
                    ),
                    _PriceBadge(cost: info.cost),
                  ],
                ),
                if (widget.selectableTiers) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (var tier = 0; tier <= 2; tier++)
                        ChoiceChip(
                          key: ValueKey('unit-tier-$tier'),
                          label: Text('${displayStarLevel(tier)} ดาว'),
                          selected: _tier == tier,
                          onSelected: (_) => setState(() => _tier = tier),
                        ),
                    ],
                  ),
                ],
                if (widget.hp != null && widget.maxHp != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  HealthBar(
                    current: widget.hp!,
                    max: widget.maxHp!,
                    size: HealthBarSize.lg,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(label: 'HP', value: '${info.hp}'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(
                        label: 'ATK',
                        value: '${info.atkForTier(_tier)}',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _StatTile(label: 'SPD', value: '${info.spd}'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'ความสามารถ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(info.abilityForTier(_tier)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.cost});

  final int cost;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: AppRadius.allFull,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text('$cost ทอง'),
        ),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.allSm,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
}
