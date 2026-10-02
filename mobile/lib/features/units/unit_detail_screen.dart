import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../shared/models/unit.dart';
import '../../shared/models/unit_catalog.dart';
import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';

/// `/units/:unitId` — a full-screen field guide for one unit archetype.
class UnitDetailScreen extends StatefulWidget {
  const UnitDetailScreen({super.key, required this.unitId});

  static const path = '/units/:unitId';

  final UnitId unitId;

  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen> {
  int _fusionTier = 0;

  UnitCatalogEntry get _entry => unitCatalog[widget.unitId]!;

  void _selectTier(int tier) {
    if (tier == _fusionTier || tier < 0 || tier > 2) return;
    setState(() => _fusionTier = tier);
  }

  @override
  Widget build(BuildContext context) {
    final theme = fantasySurfaceTheme(context);
    final entry = _entry;
    final accent = _unitAccent(widget.unitId);
    final ability = entry.abilities[_fusionTier];

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const PlayerHubHeader(),
                _DetailTopBar(
                  entry: entry,
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            children: [
                              _UnitHero(
                                entry: entry,
                                fusionTier: _fusionTier,
                                accent: accent,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _TierSelector(
                                fusionTier: _fusionTier,
                                accent: accent,
                                onSelect: _selectTier,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _StatsRow(
                                entry: entry,
                                fusionTier: _fusionTier,
                                accent: accent,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _AbilityPanel(
                                ability: ability,
                                accent: accent,
                                fusionTier: _fusionTier,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.units),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.entry,
    required this.onBack,
  });

  final UnitCatalogEntry entry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'กลับ',
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFFFFF7DD),
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          _PriceBadge(cost: entry.cost, color: game.gold),
        ],
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.cost, required this.color});

  final int cost;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE60A1724),
          borderRadius: AppRadius.allFull,
          border: Border.all(color: color.withValues(alpha: 0.72)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: AppSpacing.md,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on_rounded, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$cost',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      );
}

class _UnitHero extends StatelessWidget {
  const _UnitHero({
    required this.entry,
    required this.fusionTier,
    required this.accent,
  });

  final UnitCatalogEntry entry;
  final int fusionTier;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: AppRadius.allLg,
        border: Border.all(color: accent.withValues(alpha: 0.88), width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xF20A1724),
            Color.lerp(const Color(0xFF10283B), accent, 0.16)!,
            const Color(0xFA07111C),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: AppSpacing.xl,
            spreadRadius: AppSpacing.xxs,
          ),
          const BoxShadow(
            color: Color(0xB3000000),
            blurRadius: AppSpacing.xl,
            offset: Offset(0, AppSpacing.sm),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HeroGridPainter(accent: accent),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.18),
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.32),
                    accent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            child: _RoleBadge(
              icon: _unitIcon(entry.id),
              label: _unitClassLabel(entry.id),
              accent: accent,
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            right: AppSpacing.md,
            child: _TierBadge(tier: fusionTier, accent: accent),
          ),
          Positioned.fill(
            top: AppSpacing.xxl,
            bottom: AppSpacing.xxl,
            child: AnimatedSwitcher(
              duration: AppMotion.maybe(
                AppMotion.medium2,
                reduceMotion: reduceMotion,
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
              ),
              child: Image.asset(
                'assets/images/units/${entry.id.name}_${fusionTier + 1}.png',
                key: ValueKey('${entry.id.name}-$fusionTier'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.md,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: AppSpacing.xxl,
                  height: 1,
                  color: accent.withValues(alpha: 0.46),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'FORM ${fusionTier + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: AppSpacing.xxl,
                  height: 1,
                  color: accent.withValues(alpha: 0.46),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ประเภทยูนิต: $label',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC07131F),
            borderRadius: AppRadius.allFull,
            border: Border.all(color: accent.withValues(alpha: 0.64)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFE7F2FF),
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier, required this.accent});

  final int tier;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: AppRadius.allFull,
          border: Border.all(color: accent.withValues(alpha: 0.72)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index <= tier; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xxs),
              Icon(Icons.star_rounded, size: 18, color: accent),
            ],
          ],
        ),
      );
}

class _TierSelector extends StatelessWidget {
  const _TierSelector({
    required this.fusionTier,
    required this.accent,
    required this.onSelect,
  });

  final int fusionTier;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: const Color(0xE60A1A29),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: const Color(0x806FA5C4)),
        ),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('star-form-previous'),
              onPressed: fusionTier > 0 ? () => onSelect(fusionTier - 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'ร่างก่อนหน้า',
            ),
            Expanded(
              child: Row(
                children: [
                  for (var tier = 0; tier < 3; tier++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                        ),
                        child: _TierOption(
                          tier: tier,
                          selected: tier == fusionTier,
                          accent: accent,
                          onTap: () => onSelect(tier),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('star-form-next'),
              onPressed: fusionTier < 2 ? () => onSelect(fusionTier + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'ร่างถัดไป',
            ),
          ],
        ),
      );
}

class _TierOption extends StatelessWidget {
  const _TierOption({
    required this.tier,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final int tier;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tier + 1} ดาว',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          child: AnimatedContainer(
            duration: AppMotion.maybe(
              AppMotion.short4,
              reduceMotion: reduceMotion,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: AppRadius.allMd,
              border: Border.all(
                color: selected ? accent : const Color(0x336FA5C4),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.16),
                        blurRadius: AppSpacing.md,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.star_rounded,
                  size: selected ? 24 : 20,
                  color: selected ? accent : const Color(0xFF71869C),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${tier + 1} ดาว',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFF9FB0C1),
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.entry,
    required this.fusionTier,
    required this.accent,
  });

  final UnitCatalogEntry entry;
  final int fusionTier;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'HP',
              value: entry.hp,
              icon: Icons.favorite_rounded,
              color: const Color(0xFF63C58C),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatCard(
              label: 'ATK',
              value: entry.attackAtFusionTier(fusionTier),
              icon: Icons.bolt_rounded,
              color: accent,
              valueKey: ValueKey('attack-$fusionTier'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatCard(
              label: 'SPD',
              value: entry.spd,
              icon: Icons.speed_rounded,
              color: const Color(0xFF74C7EC),
            ),
          ),
        ],
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.valueKey,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE6112638),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: color.withValues(alpha: 0.44)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: AppSpacing.md,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(
            duration: AppMotion.maybe(
              AppMotion.short4,
              reduceMotion: reduceMotion,
            ),
            child: Text(
              '$value',
              key: valueKey,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbilityPanel extends StatelessWidget {
  const _AbilityPanel({
    required this.ability,
    required this.accent,
    required this.fusionTier,
  });

  final UnitAbility ability;
  final Color accent;
  final int fusionTier;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allLg,
        border: Border.all(color: accent.withValues(alpha: 0.62)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            const Color(0xED10283B),
            const Color(0xF207131F),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: AppSpacing.xl,
            offset: Offset(0, AppSpacing.sm),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.huge,
            height: AppSpacing.huge,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.72)),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ความสามารถประจำร่าง',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: AppRadius.allFull,
                      ),
                      child: Text(
                        '${ability.starLevel} ดาว',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: AppMotion.maybe(
                    AppMotion.short4,
                    reduceMotion: reduceMotion,
                  ),
                  child: Text(
                    ability.description,
                    key: ValueKey('ability-$fusionTier'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFDCEBFA),
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGridPainter extends CustomPainter {
  const _HeroGridPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final step = size.width / 6;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        line,
      );
    }
    final ring = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.54),
      size.shortestSide * 0.34,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroGridPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

Color _unitAccent(UnitId id) => switch (id) {
      UnitId.fighter => const Color(0xFFFF6B6B),
      UnitId.healer => const Color(0xFFF0B66A),
      UnitId.ranger => const Color(0xFF5DD6C0),
      UnitId.tank => const Color(0xFF72A7FF),
    };

IconData _unitIcon(UnitId id) => switch (id) {
      UnitId.fighter => Icons.sports_martial_arts_rounded,
      UnitId.healer => Icons.health_and_safety_rounded,
      UnitId.ranger => Icons.gps_fixed_rounded,
      UnitId.tank => Icons.shield_rounded,
    };

String _unitClassLabel(UnitId id) => switch (id) {
      UnitId.fighter => 'จู่โจม',
      UnitId.healer => 'สนับสนุน',
      UnitId.ranger => 'ระยะไกล',
      UnitId.tank => 'แนวหน้า',
    };
