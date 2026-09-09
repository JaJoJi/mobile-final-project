/// `game:shop:offer` — the caller's private shop for the current
/// `shop_place` phase (re-sent after their one free refresh).
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:shop:offer`.
library;

import 'unit.dart';

class ShopOffer {
  const ShopOffer({
    required this.offerId,
    required this.unitId,
    required this.star,
  });

  final String offerId;
  final UnitId unitId;

  /// Always `0` in the MVP (offers are unfused).
  final int star;

  factory ShopOffer.fromJson(Map<String, dynamic> j) => ShopOffer(
        offerId: j['offerId'] as String? ?? '',
        unitId: UnitId.fromJson(j['unitId'] as String?),
        star: (j['star'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'ShopOffer($unitId ★$star id=$offerId)';
}

class ShopOffersEvent {
  const ShopOffersEvent({
    required this.matchId,
    required this.round,
    required this.offers,
  });

  final String matchId;
  final int round;

  /// Five slots; an entry is `null` once that offer has been purchased.
  final List<ShopOffer?> offers;

  factory ShopOffersEvent.fromJson(Map<String, dynamic> j) {
    final raw = (j['offers'] as List?) ?? const [];
    return ShopOffersEvent(
      matchId: j['matchId'] as String? ?? '',
      round: (j['round'] as num?)?.toInt() ?? 0,
      offers: raw.map<ShopOffer?>((e) {
        return e is Map<String, dynamic> ? ShopOffer.fromJson(e) : null;
      }).toList(growable: false),
    );
  }

  @override
  String toString() =>
      'ShopOffersEvent(match: $matchId, round: $round, offers: $offers)';
}
