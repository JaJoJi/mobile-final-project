import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/unit_star_level.dart';
import '../../../core/widgets/game_art_frame.dart';
import '../../../core/widgets/health_bar.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
import '../../../shared/models/unit_catalog.dart';
import '../match_controller.dart';
import 'board_slot.dart';
import 'stone_board_tile.dart';

class BoardTab extends StatefulWidget {
  const BoardTab({
    super.key,
    required this.match,
    required this.enabled,
    required this.ready,
    required this.selection,
    required this.onSelect,
    required this.onDrop,
  });

  final MatchState match;
  final bool enabled;
  final bool ready;
  final UnitSelection? selection;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;

  @override
  State<BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<BoardTab>
    with SingleTickerProviderStateMixin {
  final Set<String> _precachedAssets = {};
  late final AnimationController _reservePulse;

  @override
  void initState() {
    super.initState();
    _reservePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheMatchArt();
  }

  @override
  void didUpdateWidget(covariant BoardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.match.roster.bench
        .whereType<Unit>()
        .map((unit) => unit.instanceId)
        .toSet();
    final purchasedUnitAppeared =
        widget.match.roster.bench.whereType<Unit>().any(
              (unit) =>
                  !oldIds.contains(unit.instanceId) &&
                  unit.instanceId.startsWith('pending-'),
            );
    if (purchasedUnitAppeared && !MediaQuery.disableAnimationsOf(context)) {
      _reservePulse.forward(from: 0);
    }
    _precacheMatchArt();
  }

  @override
  void dispose() {
    _reservePulse.dispose();
    super.dispose();
  }

  void _precacheMatchArt() {
    final paths = <String>{
      ...StoneBoardTile.allAssetPaths,
      ...GameUiAssets.reserve,
      ...allUnitArtPaths,
    };
    for (final path in paths) {
      if (_precachedAssets.add(path)) {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.match.roster;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OpponentScout(
          opponent: widget.match.opponent,
          currentRound: widget.match.round,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Icon(Icons.grid_view_rounded, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'ทีมของคุณ · รอบ ${widget.match.round}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _CountBadge(
              label: '${roster.board.whereType<Unit>().length}/9',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _BoardArena(
            roster: roster,
            enabled: widget.enabled,
            isSelected: _isSelected,
            onSelect: widget.onSelect,
            onDrop: widget.onDrop,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 78,
          child: AnimatedBuilder(
            animation: _reservePulse,
            builder: (context, child) {
              final glow = Curves.easeOut.transform(1 - _reservePulse.value);
              return DecoratedBox(
                key: const ValueKey('reserve-purchase-pulse'),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.allMd,
                  boxShadow: _reservePulse.isAnimating
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(
                              alpha: glow * 0.72,
                            ),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: child,
              );
            },
            child: _BenchBar(
              roster: roster,
              enabled: widget.enabled,
              isSelected: _isSelected,
              onSelect: widget.onSelect,
              onDrop: widget.onDrop,
            ),
          ),
        ),
      ],
    );
  }

  bool _isSelected(RosterArea area, int slot) =>
      widget.selection?.area == area && widget.selection?.slot == slot;
}

class _BoardArena extends StatelessWidget {
  const _BoardArena({
    required this.roster,
    required this.enabled,
    required this.isSelected,
    required this.onSelect,
    required this.onDrop,
  });

  final PlayerRoster roster;
  final bool enabled;
  final bool Function(RosterArea, int) isSelected;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('planning-board-surface'),
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const labelGutter = 56.0;
            final centeredWidth = constraints.maxWidth - (labelGutter * 2);
            final side = centeredWidth < constraints.maxHeight
                ? centeredWidth
                : constraints.maxHeight;
            final top = (constraints.maxHeight - side) / 2;
            final left = (constraints.maxWidth - side) / 2;
            return Stack(
              children: [
                Positioned(
                  left: left - labelGutter,
                  top: top,
                  width: labelGutter,
                  height: side,
                  child: const Column(
                    children: [
                      Expanded(child: _RowLabel(row: 0)),
                      Expanded(child: _RowLabel(row: 1)),
                      Expanded(child: _RowLabel(row: 2)),
                    ],
                  ),
                ),
                Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: GridView.builder(
                      key: const ValueKey('planning-board-grid'),
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.xs,
                        crossAxisSpacing: AppSpacing.xs,
                      ),
                      itemCount: 9,
                      itemBuilder: (context, slot) {
                        final unit = roster.board[slot];
                        return BoardSlot(
                          key: ValueKey('board-$slot'),
                          area: RosterArea.board,
                          slot: slot,
                          unit: unit,
                          enabled: enabled,
                          selected: isSelected(RosterArea.board, slot),
                          expand: true,
                          onTap: () => onSelect(RosterArea.board, slot),
                          onLongPress: unit == null
                              ? null
                              : () => _showUnitDetailSheet(
                                    context,
                                    unitId: unit.unitId,
                                    star: unit.star,
                                    hp: unit.hp,
                                    maxHp: unit.maxHp,
                                  ),
                          onDrop: (from) =>
                              onDrop(RosterArea.board, slot, from),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BenchBar extends StatelessWidget {
  const _BenchBar({
    required this.roster,
    required this.enabled,
    required this.isSelected,
    required this.onSelect,
    required this.onDrop,
  });

  final PlayerRoster roster;
  final bool enabled;
  final bool Function(RosterArea, int) isSelected;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('reserve-panel'),
      color: scheme.surface.withValues(alpha: 0.68),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                key: const ValueKey('bench-horizontal-list'),
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, slot) {
                  final unit = roster.bench[slot];
                  return SizedBox(
                    width: BoardSlot.extent + AppSpacing.xs,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.42,
                        ),
                        borderRadius: AppRadius.allSm,
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.48),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxs),
                        child: BoardSlot(
                          key: ValueKey('bench-$slot'),
                          area: RosterArea.bench,
                          slot: slot,
                          unit: unit,
                          enabled: enabled,
                          selected: isSelected(RosterArea.bench, slot),
                          expand: true,
                          onTap: () => onSelect(RosterArea.bench, slot),
                          onLongPress: unit == null
                              ? null
                              : () => _showUnitDetailSheet(
                                    context,
                                    unitId: unit.unitId,
                                    star: unit.star,
                                    hp: unit.hp,
                                    maxHp: unit.maxHp,
                                  ),
                          onDrop: (from) =>
                              onDrop(RosterArea.bench, slot, from),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.row});

  final int row;

  @override
  Widget build(BuildContext context) {
    final label = switch (row) {
      0 => 'แนวหน้า',
      1 => 'แนวกลาง',
      _ => 'แนวหลัง',
    };
    return Center(
      child: Text(
        label,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

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
          child: Text(label),
        ),
      );
}

class _OpponentScout extends StatelessWidget {
  const _OpponentScout({required this.opponent, required this.currentRound});

  final OpponentView opponent;
  final int currentRound;

  @override
  Widget build(BuildContext context) {
    final units = opponent.boardSummary.whereType<OpponentUnit>().toList();
    final hasSnapshot = opponent.scoutRound != null || units.isNotEmpty;
    final snapshotRound =
        opponent.scoutRound ?? (currentRound - 1).clamp(1, currentRound);
    final game = Theme.of(context).extension<GameTheme>()!;
    return Material(
      key: const ValueKey('scout-panel-frame'),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.68),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: game.enemy.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            hasSnapshot ? () => _showFullBoard(context, snapshotRound) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewCount = constraints.maxWidth >= 520
                  ? 3
                  : constraints.maxWidth >= 400
                      ? 2
                      : 1;
              return Row(
                children: [
                  Icon(Icons.visibility_outlined, color: game.enemy),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasSnapshot
                              ? 'ทีมคู่แข่งจากรอบ $snapshotRound'
                              : 'ยังไม่มีข้อมูลการสอดแนม',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          hasSnapshot
                              ? '${units.length}/9 ตัว · แตะเพื่อดูกระดาน'
                              : 'ข้อมูลจะพร้อมเมื่อรอบแรกจบลง',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  ...units.take(previewCount).map(
                        (unit) => Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.xs),
                          child: UnitAvatar(
                            unitId: unit.unitId.toJson(),
                            star: unit.star,
                            size: UnitAvatarSize.sm,
                            variant: UnitAvatarVariant.bench,
                            side: UnitSide.enemy,
                          ),
                        ),
                      ),
                  if (hasSnapshot) const Icon(Icons.chevron_right),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showFullBoard(BuildContext context, int snapshotRound) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'ทีมคู่แข่งจากรอบ $snapshotRound',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final heightLimit = MediaQuery.sizeOf(context).height * 0.34;
                  final maxBoardSize = heightLimit > 330 ? 330.0 : heightLimit;
                  final boardSize = constraints.maxWidth > maxBoardSize
                      ? maxBoardSize
                      : constraints.maxWidth;
                  return Center(
                    child: SizedBox.square(
                      key: const ValueKey('opponent-scout-grid'),
                      dimension: boardSize,
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: AppSpacing.xs,
                          crossAxisSpacing: AppSpacing.xs,
                        ),
                        itemCount: 9,
                        itemBuilder: (context, slot) {
                          final entry = opponent.boardSummary[slot];
                          return StoneBoardTile(
                            key: ValueKey('opponent-scout-$slot'),
                            slot: slot,
                            unitSide: entry == null ? null : UnitSide.enemy,
                            child: entry == null
                                ? _EmptyOpponentSlot(slot: slot)
                                : SizedBox.expand(
                                    child: UnitAvatar(
                                      unitId: entry.unitId.toJson(),
                                      star: entry.star,
                                      side: UnitSide.enemy,
                                      expand: true,
                                      onLongPress: () => _showUnitDetailSheet(
                                        context,
                                        unitId: entry.unitId,
                                        star: entry.star,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('ข้อมูล HP ของคู่แข่งถูกซ่อนไว้ตามกติกา'),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyOpponentSlot extends StatelessWidget {
  const _EmptyOpponentSlot({required this.slot});

  final int slot;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ช่องคู่แข่ง ${slot + 1} ว่าง',
        child: const SizedBox.expand(),
      );
}

void _showUnitDetailSheet(
  BuildContext context, {
  required UnitId unitId,
  required int star,
  int? hp,
  int? maxHp,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _UnitDetailSheet(
      unitId: unitId,
      star: star,
      hp: hp,
      maxHp: maxHp,
    ),
  );
}

class _UnitDetailSheet extends StatelessWidget {
  const _UnitDetailSheet({
    required this.unitId,
    required this.star,
    this.hp,
    this.maxHp,
  });

  final UnitId unitId;
  final int star;
  final int? hp;
  final int? maxHp;

  @override
  Widget build(BuildContext context) {
    final entry = unitCatalog[unitId]!;
    final displayStar = displayStarLevel(star);
    final ability = entry.abilities[star].description;
    return SafeArea(
      child: Padding(
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
                  unitId: unitId.toJson(),
                  star: star,
                  size: UnitAvatarSize.sm,
                  variant: UnitAvatarVariant.bench,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text('$displayStar ดาว · ${entry.role}'),
                    ],
                  ),
                ),
                _CountBadge(label: '${entry.cost} ทอง'),
              ],
            ),
            if (hp != null && maxHp != null) ...[
              const SizedBox(height: AppSpacing.md),
              HealthBar(current: hp!, max: maxHp!, size: HealthBarSize.lg),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _StatTile(label: 'HP', value: '${entry.hp}')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _StatTile(
                    label: 'ATK',
                    value: '${entry.attackAtFusionTier(star)}',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _StatTile(label: 'SPD', value: '${entry.spd}')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('ความสามารถ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(ability),
          ],
        ),
      ),
    );
  }
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
