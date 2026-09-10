import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/game_theme.dart';
import 'health_bar.dart';

/// The four unit types — `docs/05-combat-spec.md §3`.
enum UnitKind { fighter, healer, ranger, tank }

UnitKind unitKindFromId(String id) => switch (id) {
      'fighter' => UnitKind.fighter,
      'healer' => UnitKind.healer,
      'ranger' => UnitKind.ranger,
      'tank' => UnitKind.tank,
      _ => throw ArgumentError('unknown unitId: $id'),
    };

extension UnitKindDisplay on UnitKind {
  String get label => switch (this) {
        UnitKind.fighter => 'Fighter',
        UnitKind.healer => 'Healer',
        UnitKind.ranger => 'Ranger',
        UnitKind.tank => 'Tank',
      };

  String get _assetName => switch (this) {
        UnitKind.fighter => 'fighter',
        UnitKind.healer => 'healer',
        UnitKind.ranger => 'ranger',
        UnitKind.tank => 'tank',
      };

  /// Illustration for this unit — `mobile/assets/images/units/`.
  String get artPath => 'assets/images/units/$_assetName.png';

  /// Fallback shape when the art can't load — design spec §6 (● / ✚ / ▲ / ■).
  /// Also the small type glyph shown at `sm` size where there's no name label.
  IconData get shape => switch (this) {
        UnitKind.fighter => Icons.circle,
        UnitKind.healer => Icons.add,
        UnitKind.ranger => Icons.change_history,
        UnitKind.tank => Icons.square,
      };
}

/// Where a [UnitAvatar] is being shown — design spec §3.5.
enum UnitAvatarVariant { shop, bench, board, replay }

/// Interaction / status state — design spec §3.5.
enum UnitAvatarState { normal, selected, unaffordable, dragging, fusable, dead }

/// Avatar sizes — design spec §3.5.
enum UnitAvatarSize {
  /// 48 dp square — bench chip.
  sm,

  /// 64×96 — board.
  md,

  /// 88×132 — shop card.
  lg,
}

/// Renders one unit anywhere — shop, bench, board, replay. Design spec §3.5.
///
/// Shows the unit illustration (`assets/images/units/`, with the Material
/// shape as fallback), a star badge, the name, and — for
/// [UnitAvatarVariant.shop] — the price. **[MUST]** readable without
/// colour: the name label (md/lg) or the type glyph (sm) plus the star
/// count always carry the meaning.
class UnitAvatar extends StatelessWidget {
  const UnitAvatar({
    super.key,
    required this.unitId,
    required this.star,
    this.variant = UnitAvatarVariant.board,
    this.state = UnitAvatarState.normal,
    this.size = UnitAvatarSize.md,
    this.side = UnitSide.ally,
    this.price,
    this.hp,
    this.maxHp,
    this.floatingDamage,
    this.onTap,
    this.onLongPress,
  }) : assert(star >= 0 && star <= 2);

  final String unitId;
  final int star;
  final UnitAvatarVariant variant;
  final UnitAvatarState state;
  final UnitAvatarSize size;
  final UnitSide side;

  /// Shop price in gold (shown only for [UnitAvatarVariant.shop]).
  final int? price;

  /// Board variant shows a small HP bar when both are provided.
  final int? hp;
  final int? maxHp;

  /// Replay variant shows this number floating (animation lands in P0-FE-05).
  final int? floatingDamage;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  double get _width => switch (size) {
        UnitAvatarSize.sm => 48,
        UnitAvatarSize.md => 64,
        UnitAvatarSize.lg => 88,
      };

  double get _aspect => variant == UnitAvatarVariant.shop ? 64 / 96 : 1.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;
    final kind = unitKindFromId(unitId);
    final isShop = variant == UnitAvatarVariant.shop;

    final tint = side == UnitSide.ally ? game.ally : game.enemy;
    final borderColor = switch (state) {
      UnitAvatarState.selected => t.colorScheme.primary,
      UnitAvatarState.fusable => game.star2,
      _ => t.colorScheme.outlineVariant,
    };
    final borderWidth =
        state == UnitAvatarState.selected || state == UnitAvatarState.fusable
            ? 2.0
            : 1.0;

    Widget body = AspectRatio(
      aspectRatio: _aspect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.allMd,
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: state == UnitAvatarState.fusable
              ? [
                  BoxShadow(
                    color: game.star2.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        // Dense game component — clamp runaway text scaling to keep the
        // fixed AspectRatio intact (design spec §2.2 allows clamping a
        // HUD-like subtree, never a global override).
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: isShop
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StarBadge(star: star, color: game.starColor(star)),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: _UnitArt(
                            kind: kind,
                            tint: tint,
                            size: _width * 0.72,
                          ),
                        ),
                      ),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            kind.label,
                            maxLines: 1,
                            style: t.textTheme.titleMedium,
                          ),
                        ),
                      ),
                      if (price != null)
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.monetization_on,
                                size: 14,
                                color: state == UnitAvatarState.unaffordable
                                    ? t.colorScheme.error
                                    : game.gold,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(
                                '$price',
                                style: AppTypography.tabular(
                                  (t.textTheme.labelLarge ?? const TextStyle())
                                      .copyWith(
                                    color: state == UnitAvatarState.unaffordable
                                        ? t.colorScheme.error
                                        : game.gold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: _UnitArt(
                        kind: kind,
                        tint: tint,
                        size: _width,
                      ),
                    ),
                    if (star > 0)
                      Positioned(
                        left: AppSpacing.xxs,
                        top: AppSpacing.xxs,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: AppRadius.allFull,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxs),
                            child: _StarBadge(
                              star: star,
                              color: game.starColor(star),
                            ),
                          ),
                        ),
                      ),
                    if (variant == UnitAvatarVariant.board &&
                        hp != null &&
                        maxHp != null)
                      Positioned(
                        left: AppSpacing.xxs,
                        right: AppSpacing.xxs,
                        bottom: AppSpacing.xxs,
                        child: HealthBar(
                          current: hp!,
                          max: maxHp!,
                          size: HealthBarSize.sm,
                          showText: false,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );

    if (state == UnitAvatarState.dragging) {
      body = Transform.scale(scale: 1.05, child: body);
    }
    if (state == UnitAvatarState.unaffordable ||
        state == UnitAvatarState.dead) {
      body = Opacity(opacity: 0.4, child: body);
    }
    if (state == UnitAvatarState.dead) {
      body = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
        child: body,
      );
    }

    if (floatingDamage != null && variant == UnitAvatarVariant.replay) {
      body = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          body,
          Positioned(
            top: -AppSpacing.lg,
            child: Text(
              '-${floatingDamage!}',
              style: AppTypography.tabular(
                (t.textTheme.titleMedium ?? const TextStyle())
                    .copyWith(color: t.colorScheme.error),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: onTap != null,
      label: '${kind.label} ${star > 0 ? '$star ดาว' : ''}'
          '${price != null ? ' ราคา $price ทอง' : ''}'
          '${state == UnitAvatarState.fusable ? ' รวมได้' : ''}',
      child: SizedBox(
        width: _width,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppRadius.allMd,
          child: body,
        ),
      ),
    );
  }
}

/// Team side for tinting — pairs with an icon/label elsewhere, never colour alone.
enum UnitSide { ally, enemy }

/// The unit illustration with a graceful fallback to the placeholder shape
/// if the asset is missing / fails to decode (e.g. in a widget test with no
/// asset bundle).
class _UnitArt extends StatelessWidget {
  const _UnitArt({required this.kind, required this.tint, required this.size});

  final UnitKind kind;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The unit's identity is already announced by the parent
    // `UnitAvatar` Semantics label + the name text + star badge, so the
    // illustration itself is decorative to a screen reader.
    return ExcludeSemantics(
      child: Image.asset(
        kind.artPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(kind.shape, size: size * 0.6, color: tint),
      ),
    );
  }
}

class _StarBadge extends StatelessWidget {
  const _StarBadge({required this.star, required this.color});

  final int star;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // 0★ = base unit — no glyphs (the design mock only shows stars for 1★+).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        star.clamp(0, 2),
        (_) => Icon(Icons.star, size: 12, color: color),
      ),
    );
  }
}
