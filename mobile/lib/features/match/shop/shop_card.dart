import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/unit_avatar.dart';
import '../../../shared/models/shop_offer.dart';
import '../match_controller.dart';

class ShopCard extends StatelessWidget {
  const ShopCard({
    super.key,
    required this.offer,
    required this.gold,
    required this.enabled,
    required this.onBuy,
    required this.width,
    this.fusable = false,
  });

  final ShopOffer? offer;
  final int gold;
  final bool enabled;
  final VoidCallback onBuy;
  final double width;
  final bool fusable;

  @override
  Widget build(BuildContext context) {
    if (offer == null) {
      return SizedBox(
        width: width,
        child: Center(
          child: SizedBox(
            width: width,
            child: AspectRatio(
              aspectRatio: 64 / 96,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: AppRadius.allMd,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const Center(child: Text('ซื้อแล้ว')),
              ),
            ),
          ),
        ),
      );
    }
    final price = unitPrice(offer!.unitId);
    final affordable = gold >= price;
    final disabledReason = !affordable
        ? 'ทองไม่พอ ต้องการ $price ทอง'
        : !enabled
            ? 'จัดทีมได้เฉพาะช่วงวางแผน'
            : null;
    Widget card = SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && affordable ? onBuy : null,
          borderRadius: AppRadius.allMd,
          child: Center(
            child: UnitAvatar(
              unitId: offer!.unitId.toJson(),
              star: offer!.star,
              variant: UnitAvatarVariant.shop,
              size: UnitAvatarSize.lg,
              price: price,
              state: !affordable
                  ? UnitAvatarState.unaffordable
                  : fusable
                      ? UnitAvatarState.fusable
                      : UnitAvatarState.normal,
            ),
          ),
        ),
      ),
    );
    if (disabledReason != null) {
      card = Tooltip(message: disabledReason, child: card);
    }
    return card;
  }
}
