import 'package:auto_chess_mobile/features/match/shop/shop_tab.dart';
import 'package:auto_chess_mobile/shared/models/match_state.dart';
import 'package:auto_chess_mobile/shared/models/shop_offer.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../widgets/_harness.dart';

const _roster = PlayerRoster(
  board: [],
  bench: [],
  gold: 5,
  hp: 100,
);

const _shop = ShopOffersEvent(
  matchId: 'm1',
  round: 1,
  offers: [
    ShopOffer(offerId: '1', unitId: UnitId.fighter, star: 0),
    ShopOffer(offerId: '2', unitId: UnitId.healer, star: 0),
    ShopOffer(offerId: '3', unitId: UnitId.ranger, star: 0),
    ShopOffer(offerId: '4', unitId: UnitId.tank, star: 0),
    ShopOffer(offerId: '5', unitId: UnitId.fighter, star: 0),
  ],
);

Widget _buildShop({required bool vertical, required Size size}) => SizedBox(
      width: size.width,
      height: size.height,
      child: ShopTab(
        shop: _shop,
        roster: _roster,
        enabled: true,
        refreshUsed: false,
        vertical: vertical,
        onBuy: (_) {},
        onRefresh: () {},
      ),
    );

void main() {
  testWidgets('vertical: stacks cards top to bottom, not side by side',
      (tester) async {
    await pumpThemed(
      tester,
      _buildShop(vertical: true, size: const Size(220, 700)),
      surfaceSize: const Size(400, 800),
    );

    final first = tester.getTopLeft(find.byKey(const ValueKey('shop-0')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('shop-1')));
    expect(
      second.dy,
      greaterThan(first.dy),
      reason: 'shop-1 should sit below shop-0 in vertical mode',
    );
    expect(
      second.dx,
      closeTo(first.dx, 1),
      reason: 'cards should share a column, not be side by side',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'vertical: a short landscape-phone panel scrolls instead of '
      'overflowing', (tester) async {
    // A landscape *phone* gives the shop column far less height than a
    // landscape *desktop* window does — 5 stacked cards can easily be
    // taller than that, so this must scroll, not overflow.
    // Matches the real dimensions a landscape phone gives the shop
    // column: flex:3 of an ~844px-wide, ~390px-tall screen, minus the
    // outer/inner padding `_PlanningHost`/`ShopTab` both apply.
    await pumpThemed(
      tester,
      _buildShop(vertical: true, size: const Size(230, 220)),
      surfaceSize: const Size(844, 390),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('non-vertical (portrait) keeps the horizontal row, no ListView',
      (tester) async {
    await pumpThemed(
      tester,
      _buildShop(vertical: false, size: const Size(400, 140)),
      surfaceSize: const Size(430, 932),
    );

    final first = tester.getTopLeft(find.byKey(const ValueKey('shop-0')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('shop-1')));
    expect(second.dx, greaterThan(first.dx));
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
