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
  });

  final ShopOffersEvent? shop;
  final PlayerRoster roster;
  final bool enabled;
  final bool refreshUsed;
  final ValueChanged<int> onBuy;
  final VoidCallback onRefresh;

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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = AppSpacing.xs;
                  final cardWidth = (constraints.maxWidth - (gap * 4)) / 5;
                  return Row(
                    key: const ValueKey('shop-card-row'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...List.generate(5, (index) {
                        final offer =
                            index < offers.length ? offers[index] : null;
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
            ),
          ],
        ),
      ),
    );
  }
}
