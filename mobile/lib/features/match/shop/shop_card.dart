import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/game_art_frame.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/shop_offer.dart';
import '../match_controller.dart';

class ShopCard extends StatefulWidget {
  const ShopCard({
    super.key,
    required this.offer,
    required this.gold,
    required this.enabled,
    required this.onBuy,
    required this.width,
    this.landscape = false,
  });

  final ShopOffer? offer;
  final int gold;
  final bool enabled;
  final VoidCallback onBuy;
  final double width;

  /// See `UnitAvatar.landscapeShop` — the landscape/tablet shop column
  /// passes this through; the mobile-portrait row leaves it off.
  final bool landscape;

  @override
  State<ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<ShopCard> with TickerProviderStateMixin {
  late final AnimationController _shake;
  late final AnimationController _purchase;
  ShopOffer? _displayOffer;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _purchase = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _displayOffer = widget.offer;
  }

  @override
  void didUpdateWidget(covariant ShopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer != null && widget.offer == null) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _displayOffer = null;
      } else {
        _displayOffer = oldWidget.offer;
        _purchase.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _displayOffer = widget.offer);
        });
      }
    } else if (widget.offer != null) {
      _displayOffer = widget.offer;
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _purchase.dispose();
    super.dispose();
  }

  void _handleTap(bool affordable) {
    if (!widget.enabled) return;
    if (affordable) {
      widget.onBuy();
    } else if (!MediaQuery.disableAnimationsOf(context)) {
      _shake.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _displayOffer;
    if (offer == null) {
      return SizedBox(
        width: widget.width,
        child: AspectRatio(
          // Must track `UnitAvatar._aspect`'s two shop shapes — an empty
          // slot sitting at the old portrait ratio among landscape cards
          // (or vice versa) reads as a card of the wrong size, not a sold
          // slot.
          aspectRatio: widget.landscape ? 64 / 35 : 64 / 80,
          child: GameArtFrame(
            frameAsset: GameUiAssets.shopCardFrame,
            kind: GameArtFrameKind.card,
            child: Align(
              // Landscape's real card reads left-to-right (art, then
              // name); dead-centre text here read as an unstyled
              // leftover next to it. Portrait keeps the plain centre.
              alignment: widget.landscape
                  ? Alignment.centerLeft
                  : Alignment.center,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Text('ซื้อแล้ว'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final price = unitPrice(offer.unitId);
    final affordable = widget.gold >= price;
    final disabledReason = !affordable
        ? 'ทองไม่พอ ต้องการ $price ทอง'
        : !widget.enabled
            ? 'จัดทีมได้เฉพาะช่วงวางแผน'
            : null;
    Widget card = SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _pressed
              ? 0.97
              : _hovered && widget.enabled
                  ? 1.025
                  : 1,
          duration: AppMotion.maybe(
            AppMotion.short2,
            reduceMotion: MediaQuery.disableAnimationsOf(context),
          ),
          child: AnimatedSlide(
            offset: _hovered && widget.enabled
                ? const Offset(0, -0.025)
                : Offset.zero,
            duration: AppMotion.maybe(
              AppMotion.short2,
              reduceMotion: MediaQuery.disableAnimationsOf(context),
            ),
            child: Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              borderRadius: AppRadius.allMd,
              child: InkWell(
                onTap: widget.enabled ? () => _handleTap(affordable) : null,
                onHighlightChanged: widget.enabled
                    ? (pressed) => setState(() => _pressed = pressed)
                    : null,
                borderRadius: AppRadius.allMd,
                // Not `SizedBox.expand`: that forces *both* dimensions
                // tight, which defeats `UnitAvatar`'s own internal
                // `AspectRatio` (64:96 for the shop variant) the moment
                // an ancestor hands this card more height than its width
                // calls for — exactly what a wide desktop viewport does,
                // since the shop panel is as tall as the board beside it
                // regardless of how few cards it holds. `expand: true`
                // alone already fills the *width* UnitAvatar is given
                // and derives its own height from that.
                child: UnitAvatar(
                  unitId: offer.unitId.toJson(),
                  star: offer.star,
                  variant: UnitAvatarVariant.shop,
                  size: UnitAvatarSize.lg,
                  expand: true,
                  price: price,
                  state: !affordable
                      ? UnitAvatarState.unaffordable
                      : UnitAvatarState.normal,
                  landscapeShop: widget.landscape,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    card = AnimatedBuilder(
      animation: Listenable.merge([_shake, _purchase]),
      child: card,
      builder: (context, child) {
        final shakeOffset =
            math.sin(_shake.value * math.pi * 6) * (1 - _shake.value) * 5;
        final purchasePulse = math.sin(_purchase.value * math.pi);
        return Transform.translate(
          key: const ValueKey('shop-card-feedback'),
          offset: Offset(shakeOffset, 0),
          child: Transform.scale(
            scale: 1 - (purchasePulse * 0.08),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppRadius.allMd,
                boxShadow: _purchase.isAnimating
                    ? [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: purchasePulse * 0.75),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          ),
        );
      },
    );
    if (disabledReason != null) {
      card = Tooltip(message: disabledReason, child: card);
    }
    return card;
  }
}
