import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../shared/models/unit.dart';
import '../../shared/models/unit_catalog.dart';

import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';

/// `/units/:unitId` — full-screen detail for a single unit archetype.
///
/// Shows name, gold cost, a star-form switcher (★1 ↔ ★2 ↔ ★3), the unit
/// art at the selected star level, and the ability description for that
/// form. The user taps left/right arrows to browse forms.
class UnitDetailScreen extends StatefulWidget {
  const UnitDetailScreen({super.key, required this.unitId});

  /// Route path template — matches `GoRoute(path: '/units/:unitId', …)`.
  static const path = '/units/:unitId';

  final UnitId unitId;

  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen> {
  /// Index into [UnitCatalogEntry.abilities] — 0, 1, or 2.
  int _formIndex = 0;

  UnitCatalogEntry get _entry => unitCatalog[widget.unitId]!;

  int get _maxIndex => _entry.abilities.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = fantasySurfaceTheme(context);
    final game = theme.extension<GameTheme>()!;
    final entry = _entry;
    final ability = entry.abilities[_formIndex];

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            child: Column(
              children: [
                const PlayerHubHeader(),
                // ── Top bar ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'กลับ',
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'กลับ',
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: const Color(0xFFFFF5D6),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.monetization_on,
                            size: 18,
                            color: game.gold,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            '${entry.cost}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: game.gold,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Scrollable content ───────────────────────────────
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
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            children: [
                              // ── Unit art ─────────────────────────
                              FantasyPanel(
                                translucent: true,
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                          vertical: AppSpacing.xxs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0A1724),
                                          border: Border.all(
                                            color: game.starColor(_formIndex),
                                          ),
                                          borderRadius: AppRadius.allFull,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(
                                            _formIndex + 1,
                                            (index) => Icon(
                                              Icons.star,
                                              size: 14,
                                              color: game.starColor(_formIndex),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.lg),
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            height: 180,
                                            width: 180,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  theme.colorScheme.primary
                                                      .withValues(alpha: 0.25),
                                                  Colors.transparent,
                                                ],
                                                radius: 0.7,
                                              ),
                                            ),
                                          ),
                                          Image.asset(
                                            'assets/images/units/${entry.id.name}_${_formIndex + 1}.png',
                                            height: 180,
                                            fit: BoxFit.contain,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              // ── Role subtitle ───────────────────
                              Text(
                                entry.role,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFFB8CEF0),
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: AppSpacing.md),
                              _UnitStats(
                                hp: entry.hp,
                                attack: entry.attackAtFusionTier(_formIndex),
                                speed: entry.spd,
                                fusionTier: _formIndex,
                              ),

                              const SizedBox(height: AppSpacing.lg),

                              // ── Star form switcher ──────────────
                              FantasyPanel(
                                translucent: true,
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Column(
                                  children: [
                                    _StarFormSwitcher(
                                      currentIndex: _formIndex,
                                      maxIndex: _maxIndex,
                                      starLevel: ability.starLevel,
                                      starColor: game.starColor(_formIndex),
                                      onPrevious: _formIndex > 0
                                          ? () => setState(
                                                () => _formIndex--,
                                              )
                                          : null,
                                      onNext: _formIndex < _maxIndex
                                          ? () => setState(
                                                () => _formIndex++,
                                              )
                                          : null,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    // ── Ability description ─────────
                                    Semantics(
                                      label:
                                          'ความสามารถ ${ability.starLevel} ดาว: ${ability.description}',
                                      child: Column(
                                        children: [
                                          Text(
                                            'ความสามารถ',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.sm,
                                          ),
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: Text(
                                              ability.description,
                                              key: ValueKey(
                                                '${entry.id}-${ability.starLevel}',
                                              ),
                                              style: theme.textTheme.bodyLarge,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Bottom Navigation ────────────────────────────────
                const PlayerHubNavigation(selected: PlayerHubTab.units),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitStats extends StatelessWidget {
  const _UnitStats({
    required this.hp,
    required this.attack,
    required this.speed,
    required this.fusionTier,
  });

  final int hp;
  final int attack;
  final int speed;
  final int fusionTier;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: _StatTile(label: 'HP', value: hp)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatTile(
              label: 'ATK',
              value: attack,
              valueKey: ValueKey('attack-$fusionTier'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _StatTile(label: 'SPD', value: speed)),
        ],
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.valueKey,
  });

  final String label;
  final int value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FantasyPanel(
      translucent: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              '$value',
              key: valueKey,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Left / right arrows around the current star level indicator.
class _StarFormSwitcher extends StatelessWidget {
  const _StarFormSwitcher({
    required this.currentIndex,
    required this.maxIndex,
    required this.starLevel,
    required this.starColor,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int maxIndex;
  final int starLevel;
  final Color starColor;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.25);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label: 'ร่างก่อนหน้า',
          child: IconButton(
            key: const ValueKey('star-form-previous'),
            onPressed: onPrevious,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: onPrevious != null ? starColor : disabledColor,
              size: 32,
            ),
            tooltip: 'ร่างก่อนหน้า',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Star icons row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < starLevel; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Icon(Icons.star, size: 24, color: starColor),
            ],
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          button: true,
          label: 'ร่างถัดไป',
          child: IconButton(
            key: const ValueKey('star-form-next'),
            onPressed: onNext,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: onNext != null ? starColor : disabledColor,
              size: 32,
            ),
            tooltip: 'ร่างถัดไป',
          ),
        ),
      ],
    );
  }
}
