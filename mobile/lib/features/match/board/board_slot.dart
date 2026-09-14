import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/unit.dart';
import '../match_controller.dart';
import 'stone_board_tile.dart';

class UnitDragData {
  const UnitDragData(this.selection, this.unit);

  final UnitSelection selection;
  final Unit unit;
}

enum _SlotEffect { none, placement, fuse }

class BoardSlot extends StatefulWidget {
  const BoardSlot({
    super.key,
    required this.area,
    required this.slot,
    required this.unit,
    required this.enabled,
    required this.selected,
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
  final VoidCallback onTap;
  final ValueChanged<UnitSelection> onDrop;
  final VoidCallback? onLongPress;
  final bool opponent;
  final bool expand;

  @override
  State<BoardSlot> createState() => _BoardSlotState();
}

class _BoardSlotState extends State<BoardSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _effectController;
  _SlotEffect _effect = _SlotEffect.none;

  @override
  void initState() {
    super.initState();
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void didUpdateWidget(covariant BoardSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appeared = oldWidget.unit == null && widget.unit != null;
    final fused = oldWidget.unit != null &&
        widget.unit != null &&
        oldWidget.unit!.unitId == widget.unit!.unitId &&
        widget.unit!.star > oldWidget.unit!.star;
    if ((appeared || fused) && !MediaQuery.disableAnimationsOf(context)) {
      _effect = fused ? _SlotEffect.fuse : _SlotEffect.placement;
      _effectController.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _effect = _SlotEffect.none);
      });
    }
  }

  @override
  void dispose() {
    _effectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = Theme.of(context).extension<GameTheme>()!;
    final isBoard = widget.area == RosterArea.board;
    Widget content = widget.unit == null
        ? Semantics(
            key: const ValueKey('empty-slot'),
            button: widget.enabled,
            label: 'ช่องว่าง ${widget.slot + 1}',
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              borderRadius: AppRadius.allSm,
              child: const SizedBox.expand(),
            ),
          )
        : _ResponsiveSlotUnit(
            key: ValueKey('${widget.unit!.instanceId}-${widget.unit!.star}'),
            fillSlot: isBoard,
            child: UnitAvatar(
              unitId: widget.unit!.unitId.toJson(),
              star: widget.unit!.star,
              hp: widget.opponent ? null : widget.unit!.hp,
              maxHp: widget.opponent ? null : widget.unit!.maxHp,
              variant: widget.area == RosterArea.bench
                  ? UnitAvatarVariant.bench
                  : UnitAvatarVariant.board,
              side: widget.opponent ? UnitSide.enemy : UnitSide.ally,
              state: widget.selected
                  ? UnitAvatarState.selected
                  : UnitAvatarState.normal,
              onTap: widget.enabled ? widget.onTap : null,
              onLongPress: widget.onLongPress,
              expand: isBoard,
            ),
          );

    content = AnimatedSwitcher(
      duration: AppMotion.maybe(
        AppMotion.short4,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
      switchInCurve: AppMotion.emphasizedDecelerate,
      switchOutCurve: AppMotion.emphasizedAccelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: content,
    );

    if (widget.enabled && widget.unit != null && !widget.opponent) {
      content = Draggable<UnitDragData>(
        data: UnitDragData(
          UnitSelection(widget.area, widget.slot),
          widget.unit!,
        ),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: BoardSlot.extent,
            height: BoardSlot.extent,
            child: content,
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: content),
        child: content,
      );
    }

    return DragTarget<UnitDragData>(
      onWillAcceptWithDetails: (details) {
        if (!widget.enabled || widget.opponent) return false;
        final source = details.data.selection;
        if (source.area == widget.area && source.slot == widget.slot) {
          return false;
        }
        final target = widget.unit;
        return target == null ||
            (target.unitId == details.data.unit.unitId &&
                target.star == details.data.unit.star &&
                target.star < 2);
      },
      onAcceptWithDetails: (details) => widget.onDrop(details.data.selection),
      builder: (context, candidates, _) {
        if (isBoard) {
          return StoneBoardTile(
            slot: widget.slot,
            unitSide: widget.unit == null
                ? null
                : widget.opponent
                    ? UnitSide.enemy
                    : UnitSide.ally,
            selected: widget.selected,
            validDrop: candidates.isNotEmpty,
            effect: _effectController,
            fuseEffect: _effect == _SlotEffect.fuse,
            child: content,
          );
        }
        return AnimatedContainer(
          duration: AppMotion.short2,
          width: widget.expand ? null : BoardSlot.extent,
          height: widget.expand ? null : BoardSlot.extent,
          padding: EdgeInsets.all(widget.expand ? 0 : AppSpacing.xxs),
          decoration: BoxDecoration(
            color: candidates.isEmpty ? null : game.boardCellValidDrop,
            borderRadius: AppRadius.allSm,
          ),
          child: content,
        );
      },
    );
  }
}

/// Board pieces consume the slot constraints, while reserve pieces retain
/// their compact logical size. This keeps board art proportional on tablets
/// and desktop without changing the reserve bar layout.
class _ResponsiveSlotUnit extends StatelessWidget {
  const _ResponsiveSlotUnit({
    super.key,
    required this.fillSlot,
    required this.child,
  });

  final bool fillSlot;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      fillSlot ? SizedBox.expand(child: child) : FittedBox(child: child);
}
