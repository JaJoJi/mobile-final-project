import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/match_state.dart';
import '../../../shared/models/shop_offer.dart';
import '../../../shared/models/unit.dart';
import 'shop_card.dart';

class ShopTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final offers = shop?.offers ?? List<ShopOffer?>.filled(5, null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            0,
          ),
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
                        refreshUsed ? 'รีเฟรชแล้ว' : 'แตะการ์ดเพื่อซื้อ',
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
                    final offer = index < offers.length ? offers[index] : null;
                    final owned = offer == null
                        ? 0
                        : [...roster.board, ...roster.bench]
                            .whereType<Unit>()
                            .where((unit) => unit.unitId == offer.unitId)
                            .length;
                    return Padding(
                      padding: EdgeInsets.only(right: index == 4 ? 0 : gap),
                      child: ShopCard(
                        key: ValueKey('shop-$index'),
                        offer: offer,
                        gold: roster.gold,
                        enabled: enabled,
                        width: cardWidth,
                        fusable: owned > 0,
                        onBuy: () => onBuy(index),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
