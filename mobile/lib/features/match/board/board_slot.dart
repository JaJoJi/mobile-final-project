import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/unit.dart';
import '../match_controller.dart';

class UnitDragData {
  const UnitDragData(this.selection);

  final UnitSelection selection;
}

class BoardSlot extends StatelessWidget {
  const BoardSlot({
    super.key,
    required this.area,
    required this.slot,
    required this.unit,
    required this.enabled,
    required this.selected,
    required this.fusable,
    required this.onTap,
    required this.onDrop,
    this.onLongPress,
    this.opponent = false,
    this.expand = false,
  });

  static const double extent = 64;

  final RosterArea area;
  final int slot;
  final Unit? unit;
  final bool enabled;
  final bool selected;
  final bool fusable;
  final VoidCallback onTap;
  final ValueChanged<UnitSelection> onDrop;
  final VoidCallback? onLongPress;
  final bool opponent;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    Widget content = unit == null
        ? Semantics(
            button: enabled,
            label: 'ช่องว่าง ${slot + 1}',
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: AppRadius.allSm,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: game.boardCellEmpty,
                  borderRadius: AppRadius.allSm,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          )
        : FittedBox(
            child: UnitAvatar(
              unitId: unit!.unitId.toJson(),
              star: unit!.star,
              hp: opponent ? null : unit!.hp,
              maxHp: opponent ? null : unit!.maxHp,
              variant: area == RosterArea.bench
                  ? UnitAvatarVariant.bench
                  : UnitAvatarVariant.board,
              side: opponent ? UnitSide.enemy : UnitSide.ally,
              state: selected
                  ? UnitAvatarState.selected
                  : fusable
                      ? UnitAvatarState.fusable
                      : UnitAvatarState.normal,
              onTap: enabled ? onTap : null,
              onLongPress: onLongPress,
            ),
          );

    if (enabled && unit != null && !opponent) {
      content = Draggable<UnitDragData>(
        data: UnitDragData(UnitSelection(area, slot)),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(width: extent, height: extent, child: content),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: content),
        child: content,
      );
    }

    return DragTarget<UnitDragData>(
      onWillAcceptWithDetails: (_) => enabled && unit == null && !opponent,
      onAcceptWithDetails: (details) => onDrop(details.data.selection),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: AppMotion.short2,
        width: expand ? null : extent,
        height: expand ? null : extent,
        padding: EdgeInsets.all(expand ? 0 : AppSpacing.xxs),
        decoration: BoxDecoration(
          color: candidates.isEmpty ? null : game.boardCellValidDrop,
          borderRadius: AppRadius.allSm,
        ),
        child: content,
      ),
    );
  }
}
