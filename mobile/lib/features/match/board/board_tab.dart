import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/widgets/game_art_frame.dart';
import '../../../core/widgets/health_bar.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/unit.dart';
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
    required this.onSell,
  });

  final MatchState match;
  final bool enabled;
  final bool ready;
  final UnitSelection? selection;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;
  final void Function(RosterArea, int) onSell;

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
      for (final kind in UnitKind.values) kind.artPath,
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
    final selected = _selectedUnit(roster);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OpponentScout(opponent: widget.match.opponent),
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
            locked: widget.ready,
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
              selected: selected,
              selection: widget.selection,
              enabled: widget.enabled,
              isSelected: _isSelected,
              onSelect: widget.onSelect,
              onDrop: widget.onDrop,
              onSell: widget.onSell,
            ),
          ),
        ),
      ],
    );
  }

  bool _isSelected(RosterArea area, int slot) =>
      widget.selection?.area == area && widget.selection?.slot == slot;

  Unit? _selectedUnit(PlayerRoster roster) {
    final selection = widget.selection;
    if (selection == null) return null;
    final list =
        selection.area == RosterArea.board ? roster.board : roster.bench;
    return selection.slot < list.length ? list[selection.slot] : null;
  }
}

class _BoardArena extends StatelessWidget {
  const _BoardArena({
    required this.roster,
    required this.enabled,
    required this.locked,
    required this.isSelected,
    required this.onSelect,
    required this.onDrop,
  });

  final PlayerRoster roster;
  final bool enabled;
  final bool locked;
  final bool Function(RosterArea, int) isSelected;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      key: const ValueKey('planning-board-dimmer'),
      opacity: locked ? 0.68 : 1,
      duration: AppMotion.maybe(
        AppMotion.short4,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
      child: Card(
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
                                : () => _showUnitDetails(context, unit),
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
      ),
    );
  }
}

class _BenchBar extends StatelessWidget {
  const _BenchBar({
    required this.roster,
    required this.selected,
    required this.selection,
    required this.enabled,
    required this.isSelected,
    required this.onSelect,
    required this.onDrop,
    required this.onSell,
  });

  final PlayerRoster roster;
  final Unit? selected;
  final UnitSelection? selection;
  final bool enabled;
  final bool Function(RosterArea, int) isSelected;
  final void Function(RosterArea, int) onSelect;
  final void Function(RosterArea, int, UnitSelection) onDrop;
  final void Function(RosterArea, int) onSell;

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
            if (selected != null) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'ขาย +${unitPrice(selected!.unitId)} ทอง',
                onPressed: enabled && selection != null
                    ? () => onSell(selection!.area, selection!.slot)
                    : null,
                icon: const Icon(Icons.sell_outlined),
              ),
              VerticalDivider(color: scheme.outlineVariant),
            ],
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
                              : () => _showUnitDetails(context, unit),
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
  const _OpponentScout({required this.opponent});

  final OpponentView opponent;

  @override
  Widget build(BuildContext context) {
    final units = opponent.boardSummary.whereType<OpponentUnit>().toList();
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
        onTap: () => _showFullBoard(context),
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
                            'สอดแนมคู่แข่ง',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${units.length}/9 ตัว · แตะเพื่อดูกระดาน',
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
                    const Icon(Icons.chevron_right),
                  ],
                );
              },
          ),
        ),
      ),
    );
  }

  void _showFullBoard(BuildContext context) {
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
                  Text(
                    'กระดานคู่แข่ง',
                    style: Theme.of(context).textTheme.titleLarge,
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

void _showUnitDetails(BuildContext context, Unit unit) {
  _showUnitDetailSheet(
    context,
    unitId: unit.unitId,
    star: unit.star,
    hp: unit.hp,
    maxHp: unit.maxHp,
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
    final info = _UnitInfo.of(unitId, star);
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
                        info.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${star == 0 ? 'พื้นฐาน' : '$star ดาว'} · ${info.role}',
                      ),
                    ],
                  ),
                ),
                _CountBadge(label: '${unitPrice(unitId)} ทอง'),
              ],
            ),
            if (hp != null && maxHp != null) ...[
              const SizedBox(height: AppSpacing.md),
              HealthBar(current: hp!, max: maxHp!, size: HealthBarSize.lg),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _StatTile(label: 'HP', value: '${info.hp}')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _StatTile(label: 'ATK', value: '${info.atk}')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _StatTile(label: 'SPD', value: '${info.spd}')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('ความสามารถ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(info.ability),
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

class _UnitInfo {
  const _UnitInfo({
    required this.name,
    required this.role,
    required this.hp,
    required this.atk,
    required this.spd,
    required this.ability,
  });

  final String name;
  final String role;
  final int hp;
  final int atk;
  final int spd;
  final String ability;

  static _UnitInfo of(UnitId id, int star) => switch (id) {
        UnitId.fighter => _UnitInfo(
            name: 'นักรบ',
            role: 'สมดุลและดูดเลือด',
            hp: 100,
            atk: 15,
            spd: 20,
            ability: switch (star) {
              1 => 'ดูดเลือด 5% หลังโจมตีสำเร็จ',
              2 => 'ดูดเลือด 10% หลังโจมตีสำเร็จ',
              _ => 'ยังไม่มีความสามารถพิเศษ',
            },
          ),
        UnitId.healer => _UnitInfo(
            name: 'นักบวช',
            role: 'สนับสนุนและฟื้นฟู',
            hp: 70,
            atk: 6,
            spd: 50,
            ability: switch (star) {
              1 => 'ฮีลเพื่อนที่ HP ต่ำสุด 10 และทำให้เป้าหมายช้าลง',
              2 => 'ฮีลเพื่อน HP ต่ำสุดสองตัว ตัวละ 10',
              _ => 'ฮีลเพื่อนที่ HP ต่ำสุด 10 หลังโจมตี',
            },
          ),
        UnitId.ranger => _UnitInfo(
            name: 'พลธนู',
            role: 'สร้างความเสียหายระยะไกล',
            hp: 60,
            atk: 12,
            spd: 90,
            ability: switch (star) {
              1 => 'ความเสียหาย 10% ทะลุไปยังศัตรูด้านหลัง',
              2 => 'เล็งศัตรู HP ต่ำสุดได้จากทุกช่อง',
              _ => 'ยังไม่มีความสามารถพิเศษ',
            },
          ),
        UnitId.tank => _UnitInfo(
            name: 'อัศวินโล่',
            role: 'แนวหน้าและรับความเสียหาย',
            hp: 150,
            atk: 8,
            spd: 0,
            ability: switch (star) {
              1 => 'ฟื้นคืนชีพด้วย HP 50% ได้หนึ่งครั้งต่อรอบ',
              2 => 'บังคับศัตรูให้เล็งตน และยังฟื้นคืนชีพได้',
              _ => 'ยังไม่มีความสามารถพิเศษ',
            },
          ),
      };
}
