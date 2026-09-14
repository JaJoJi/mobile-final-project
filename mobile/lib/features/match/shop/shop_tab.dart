import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/game_art_frame.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/shop_offer.dart';
import 'shop_card.dart';

class ShopTab extends StatefulWidget {
  const ShopTab({
    super.key,
    required this.shop,
    required this.roster,
    required this.enabled,
    required this.refreshUsed,
    required this.onBuy,
    required this.onRefresh,
    this.vertical = false,
  });

  final ShopOffersEvent? shop;
  final PlayerRoster roster;
  final bool enabled;
  final bool refreshUsed;
  final ValueChanged<int> onBuy;
  final VoidCallback onRefresh;

  /// Stack the 5 cards top-to-bottom instead of side-by-side. Landscape's
  /// shop column is as tall as the board beside it and, on a wide
  /// desktop window, much taller than 5 cards need — a single column
  /// uses that shape properly and lets the panel itself go narrower,
  /// handing the freed width back to the board. Portrait's shop strip is
  /// short and full-width, the opposite shape, so it keeps the row.
  final bool vertical;

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  final Set<String> _precachedAssets = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheVisibleArt();
  }

  @override
  void didUpdateWidget(covariant ShopTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _precacheVisibleArt();
  }

  void _precacheVisibleArt() {
    final paths = <String>{
      ...GameUiAssets.shop,
      for (final offer in widget.shop?.offers ?? const <ShopOffer?>[])
        if (offer != null) unitKindFromId(offer.unitId.toJson()).artPath,
    };
    for (final path in paths) {
      if (_precachedAssets.add(path)) {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offers = widget.shop?.offers ?? List<ShopOffer?>.filled(5, null);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('shop-panel'),
      color: scheme.surface.withValues(alpha: 0.68),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.allMd,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'ร้านค้า',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (constraints.maxWidth >= 300)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            widget.refreshUsed
                                ? 'รีเฟรชแล้ว'
                                : 'แตะการ์ดเพื่อซื้อ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(child: widget.vertical ? _verticalCards(offers) : _horizontalCards(offers)),
          ],
        ),
      ),
    );
  }

  /// Portrait: unchanged from before `vertical` existed — 5 cards fill
  /// the panel's width side-by-side, sized from it directly (the shop
  /// strip there is always exactly as tall as they need).
  Widget _horizontalCards(List<ShopOffer?> offers) {
    // A landscape/desktop viewport gives this panel the same height as
    // the board beside it, whether or not 5 cards need that much room —
    // `Center` lets the row keep the height its own aspect ratio calls
    // for and sit in the middle of whatever is left, instead of the row
    // being stretched to fill it (reported live as cards rendering as
    // tall, narrow strips instead of cards). On a snug portrait layout,
    // where there's nothing to center within, this changes nothing.
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = AppSpacing.xs;
          final cardWidth = (constraints.maxWidth - (gap * 4)) / 5;
          return Row(
            key: const ValueKey('shop-card-row'),
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(5, (index) {
                final offer = index < offers.length ? offers[index] : null;
                return Padding(
                  padding: EdgeInsets.only(right: index == 4 ? 0 : gap),
                  child: ShopCard(
                    key: ValueKey('shop-$index'),
                    offer: offer,
                    gold: widget.roster.gold,
                    enabled: widget.enabled,
                    width: cardWidth,
                    onBuy: () => widget.onBuy(index),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// Landscape: one card per row, full panel width, scrollable — a
  /// narrow desktop shop column may still be shorter than 5 stacked
  /// cards want (a landscape *phone*, unlike a landscape desktop window,
  /// has very little height to spare), so this scrolls rather than
  /// overflowing.
  Widget _verticalCards(List<ShopOffer?> offers) {
    const gap = AppSpacing.xs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        return ListView.separated(
          key: const ValueKey('shop-card-row'),
          itemCount: 5,
          separatorBuilder: (context, index) =>
              const SizedBox(height: gap),
          itemBuilder: (context, index) {
            final offer = index < offers.length ? offers[index] : null;
            return ShopCard(
              key: ValueKey('shop-$index'),
              offer: offer,
              gold: widget.roster.gold,
              enabled: widget.enabled,
              width: cardWidth,
              onBuy: () => widget.onBuy(index),
            );
          },
        );
      },
    );
  }
}
