import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/game_theme.dart';
import '../utils/unit_star_level.dart';
import 'game_art_frame.dart';
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

  /// Illustration for this unit and the server's zero-based fusion tier.
  ///
  /// Keeping this mapping beside [UnitKind] makes every consumer use the
  /// same evolution art instead of constructing asset paths independently.
  String artPathForTier(int fusionTier) =>
      'assets/images/units/${_assetName}_${displayStarLevel(fusionTier)}.png';

  /// The safe fallback used when an evolved illustration cannot be decoded.
  String get baseArtPath => artPathForTier(0);

  /// Fallback shape when the art can't load — design spec §6 (● / ✚ / ▲ / ■).
  /// Also the small type glyph shown at `sm` size where there's no name label.
  IconData get shape => switch (this) {
        UnitKind.fighter => Icons.circle,
        UnitKind.healer => Icons.add,
        UnitKind.ranger => Icons.change_history,
        UnitKind.tank => Icons.square,
      };
}

/// Every unit evolution image used in a match. The match screen precaches this
/// collection before planning, battle, scouting, or results can display it.
final List<String> allUnitArtPaths = List<String>.unmodifiable([
  for (final kind in UnitKind.values)
    for (var tier = 0; tier <= 2; tier++) kind.artPathForTier(tier),
]);

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
    this.expand = false,
    this.landscapeShop = false,
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

  /// Fill the width supplied by the parent while preserving this avatar's
  /// aspect ratio. Board slots use this to scale with their stone platform;
  /// shop rows use it so all five cards share the available room.
  final bool expand;

  /// [UnitAvatarVariant.shop] only: the mobile-portrait shop strip (5
  /// cards side by side) keeps the original portrait card — art on top,
  /// name+price below — untouched. Only the landscape/tablet shop
  /// column (`ShopTab.vertical`), which has real width to spare beside
  /// a narrow board, switches to the wide art-left/name-right card. See
  /// [_aspect] and the `isShop` branch below for the two layouts.
  final bool landscapeShop;

  double get _width => switch (size) {
        UnitAvatarSize.sm => 48,
        UnitAvatarSize.md => 64,
        UnitAvatarSize.lg => 88,
      };

  /// Shop card shape (width:height). Portrait's shop strip keeps the
  /// original 64:80 (art on top, name+price merged into one row below).
  /// The landscape shop column's card is wider still — 64:35 — because
  /// there art sits *beside* the name/price instead of above it (see
  /// `avatarContent` below), so it needs even less height per width.
  double get _aspect {
    if (variant != UnitAvatarVariant.shop) return 1.0;
    return landscapeShop ? 64 / 35 : 64 / 80;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;
    final kind = unitKindFromId(unitId);
    final isShop = variant == UnitAvatarVariant.shop;
    final isBoardPiece = variant == UnitAvatarVariant.board ||
        variant == UnitAvatarVariant.replay;
    final isReservePiece = variant == UnitAvatarVariant.bench;
    final displayStar = displayStarLevel(star);

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

    Widget priceRow({required Alignment alignment}) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
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
                  (t.textTheme.labelLarge ?? const TextStyle()).copyWith(
                    color: state == UnitAvatarState.unaffordable
                        ? t.colorScheme.error
                        : game.gold,
                  ),
                ),
              ),
            ],
          ),
        );

    // Landscape shop column only (`ShopTab.vertical`) — real width to
    // spare beside a narrow board, so art sits beside name+price instead
    // of above it. Art is nudged off dead-centre toward the text side;
    // centred outright left it looking like it belonged to neither half.
    Widget landscapeShopContent() => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xxs,
            AppSpacing.xs,
            AppSpacing.xxs,
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: const Alignment(0.3, 0),
                      child: _UnitArt(
                        kind: kind,
                        fusionTier: star,
                        tint: tint,
                        size: _width * 0.76,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            kind.label,
                            maxLines: 1,
                            style: t.textTheme.titleMedium,
                          ),
                        ),
                        if (price != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          priceRow(alignment: Alignment.centerLeft),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.topLeft,
                child: _StarBadge(
                  star: displayStar,
                  color: game.starColor(star),
                ),
              ),
            ],
          ),
        );

    // Mobile-portrait shop strip (5 cards side by side) — the original
    // card, unchanged: art on top, name+price merged into one row below.
    Widget portraitShopContent() => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _StarBadge(
                  star: displayStar,
                  color: game.starColor(star),
                ),
              ),
              Expanded(
                child: Center(
                  child: _UnitArt(
                    kind: kind,
                    fusionTier: star,
                    tint: tint,
                    size: _width * 0.76,
                  ),
                ),
              ),
              SizedBox(
                height: AppSpacing.xl,
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          kind.label,
                          maxLines: 1,
                          style: t.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      priceRow(alignment: Alignment.center),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

    final avatarContent = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: isShop
          ? (landscapeShop ? landscapeShopContent() : portraitShopContent())
          : Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  // The board/bench/replay frame is a perfect square
                  // matching the source art's own 1:1 canvas, so
                  // `BoxFit.contain` renders it edge-to-edge with none of
                  // the shop variant's letterboxing to spare — every
                  // `assets/images/units/*.png` draws its character with
                  // only ~4% margin at the very top, which read as the
                  // unit's head jammed against its tile at every size.
                  // Extra top-only inset gives real headroom without
                  // shrinking the piece from its resting position at the
                  // bottom of the tile, the way it should stand.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxs,
                    AppSpacing.sm,
                    AppSpacing.xxs,
                    AppSpacing.xxs,
                  ),
                  child: isBoardPiece && expand
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final responsiveSize =
                                constraints.biggest.shortestSide;
                            return Transform.translate(
                              // Lift only the illustration so the piece's
                              // foot sits near the centre of the magic ring;
                              // stars and HP remain anchored to the slot.
                              offset: Offset(0, -responsiveSize * 0.12),
                              child: Transform.scale(
                                // Board and replay slots grow with the stone
                                // platform. Scaling from the feet makes the
                                // extra size rise into the available headroom.
                                scale: 1.24,
                                alignment: Alignment.bottomCenter,
                                child: _UnitArt(
                                  kind: kind,
                                  fusionTier: star,
                                  tint: tint,
                                  size: responsiveSize,
                                ),
                              ),
                            );
                          },
                        )
                      : _UnitArt(
                          kind: kind,
                          fusionTier: star,
                          tint: tint,
                          size: _width,
                        ),
                ),
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
                        star: displayStar,
                        color: game.starColor(star),
                      ),
                    ),
                  ),
                ),
                if (isBoardPiece && hp != null && maxHp != null)
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
    );

    Widget body = AspectRatio(
      aspectRatio: _aspect,
      child: isShop
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadius.allMd,
                border: state == UnitAvatarState.selected ||
                        state == UnitAvatarState.fusable
                    ? Border.all(color: borderColor, width: borderWidth)
                    : null,
                boxShadow: state == UnitAvatarState.fusable
                    ? [
                        BoxShadow(
                          color: game.star2.withValues(alpha: 0.6),
                          blurRadius: AppSpacing.sm,
                        ),
                      ]
                    : null,
              ),
              child: GameArtFrame(
                frameAsset: GameUiAssets.shopCardFrame,
                kind: GameArtFrameKind.card,
                child: avatarContent,
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: isBoardPiece || isReservePiece
                    ? Colors.transparent
                    : t.colorScheme.surfaceContainerHigh,
                borderRadius: AppRadius.allMd,
                border: isBoardPiece ||
                        (isReservePiece &&
                            state != UnitAvatarState.selected &&
                            state != UnitAvatarState.fusable)
                    ? null
                    : Border.all(color: borderColor, width: borderWidth),
                boxShadow: !isBoardPiece && state == UnitAvatarState.fusable
                    ? [
                        BoxShadow(
                          color: game.star2.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: avatarContent,
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
      label: '${kind.label} $displayStar ดาว'
          '${price != null ? ' ราคา $price ทอง' : ''}'
          '${state == UnitAvatarState.fusable ? ' รวมได้' : ''}',
      child: SizedBox(
        width: expand ? double.infinity : _width,
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
  const _UnitArt({
    required this.kind,
    required this.fusionTier,
    required this.tint,
    required this.size,
  });

  final UnitKind kind;
  final int fusionTier;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The unit's identity is already announced by the parent
    // `UnitAvatar` Semantics label + the name text + star badge, so the
    // illustration itself is decorative to a screen reader.
    Widget fallbackIcon() => Icon(kind.shape, size: size * 0.6, color: tint);

    Widget art(String path, {required bool allowBaseFallback}) => Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => allowBaseFallback
              ? Image.asset(
                  kind.baseArtPath,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => fallbackIcon(),
                )
              : fallbackIcon(),
        );

    return ExcludeSemantics(
      child: art(
        kind.artPathForTier(fusionTier),
        allowBaseFallback: fusionTier > 0,
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
    // This receives the one-based display level, never the server's 0..2 tier.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        star.clamp(1, 3),
        (_) => Icon(Icons.star, size: 12, color: color),
      ),
    );
  }
}
