import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/match/match_screen.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/ws/fake_ws_transport.dart';
import '../_util.dart';

void main() {
  testWidgets('portrait planning fits every section without vertical scrolling',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(430, 932),
    );
    await tester.pump();

    expect(find.textContaining('ทีมของคุณ'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-8')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('board-0'))).width,
      greaterThan(80),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('planning-board-grid'))).dx,
      closeTo(215, 1),
    );
    expect(find.byKey(const ValueKey('bench-horizontal-list')), findsOneWidget);
    expect(
      tester
          .widget<ListView>(
            find.byKey(const ValueKey('bench-horizontal-list')),
          )
          .scrollDirection,
      Axis.horizontal,
    );
    await tester.drag(
      find.byKey(const ValueKey('bench-horizontal-list')),
      const Offset(-600, 0),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('bench-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-card-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-4')), findsOneWidget);
    expect(find.text('พร้อม (0/2)'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('ร้านค้า'), findsOneWidget);
    expect(find.text('Fighter'), findsWidgets);
    expect(find.text('Healer'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-hp-value')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponent-hp-value')), findsOneWidget);
    expect(
      tester.getCenter(find.text('คุณ')).dx,
      lessThan(tester.getCenter(find.text('คู่แข่ง')).dx),
    );
    final verticalLists = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((list) => list.scrollDirection == Axis.vertical);
    expect(verticalLists, isEmpty);
    expect(
      tester.getBottomRight(find.text('พร้อม (0/2)')).dy,
      lessThanOrEqualTo(932),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending buy keeps the planning layout height stable',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(430, 932),
    );
    await tester.pump();

    final boardFinder = find.byKey(const ValueKey('planning-board-grid'));
    final before = tester.getRect(boardFinder);
    final firstShopCard = find.byKey(const ValueKey('shop-0'));
    expect(
      find.descendant(of: firstShopCard, matching: find.byType(Tooltip)),
      findsNothing,
    );
    final activeFace = find.descendant(
      of: firstShopCard,
      matching: find.byType(AspectRatio),
    );
    final cardSize = tester.getSize(activeFace);

    await tester.tap(firstShopCard);
    await tester.pump();

    expect(tester.getRect(boardFinder), before);
    final purchasedFace = find.descendant(
      of: firstShopCard,
      matching: find.byType(AspectRatio),
    );
    expect(tester.getSize(purchasedFace), cardSize);
    expect(find.text('ซื้อแล้ว'), findsOneWidget);
    expect(find.text('กำลังบันทึกสถานะพร้อม'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press opens unit details and opponent scout opens board',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport, withUnits: true);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(360, 640),
    );
    await tester.pump();

    final benchUnit = find.byKey(const ValueKey('bench-0'));
    await tester.ensureVisible(benchUnit);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(benchUnit);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('นักรบ'), findsOneWidget);
    expect(find.text('ATK'), findsOneWidget);
    Navigator.of(tester.element(find.text('นักรบ'))).pop();
    await tester.pump(const Duration(milliseconds: 500));

    final scout = find.text('สอดแนมคู่แข่ง');
    await tester.ensureVisible(scout);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(scout);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('กระดานคู่แข่ง'), findsOneWidget);
    final scoutGrid = tester.getSize(
      find.byKey(const ValueKey('opponent-scout-grid')),
    );
    expect(scoutGrid.width, scoutGrid.height);
    expect(
      tester.getCenter(find.byKey(const ValueKey('opponent-scout-0'))).dy,
      tester.getCenter(find.byKey(const ValueKey('opponent-scout-2'))).dy,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('opponent-scout-3'))).dy,
      greaterThan(
        tester.getCenter(find.byKey(const ValueKey('opponent-scout-0'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows round damage then the complete match result',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport, withUnits: true);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(360, 640),
    );
    transport.emitFromServer(GameEvents.matchDamage, {
      'matchId': 'm1',
      'round': 1,
      'damage': {
        'p1': {
          'wiped': false,
          'tie': false,
          'hpBefore': 100,
          'hpAfter': 100,
          'damageApplied': 0,
        },
        'p2': {
          'wiped': true,
          'tie': false,
          'hpBefore': 100,
          'hpAfter': 95,
          'damageApplied': 5,
        },
      },
      'winner': 'p1',
    });
    await tester.pump();
    expect(find.text('ชนะรอบนี้!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('ชนะรอบนี้!'), findsNothing);

    transport.emitFromServer(GameEvents.matchEnd, {
      'matchId': 'm1',
      'winnerId': 'p1',
      'reason': 'hp_zero',
      'final': {
        'p1': {'hp': 72, 'gold': 4},
        'p2': {'hp': 0, 'gold': 2},
      },
    });
    await tester.pump();
    expect(find.text('ชนะ!'), findsOneWidget);
    expect(find.text('ทีมสุดท้าย'), findsOneWidget);
    expect(find.text('HP สุดท้าย 72 / 100'), findsOneWidget);
    expect(find.text('เล่นอีกครั้ง'), findsOneWidget);
    expect(find.text('กลับหน้าหลัก'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape keeps board and shop visible without overflow',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport, withUnits: true);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(844, 390),
    );
    await tester.pump();

    expect(find.textContaining('ทีมของคุณ'), findsOneWidget);
    expect(find.text('ร้านค้า'), findsOneWidget);
    expect(find.text('พร้อม (0/2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait battle stacks opponent above the player',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport, withUnits: true);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(360, 640),
    );
    transport.emitFromServer(GameEvents.matchPhase, {
      'matchId': 'm1',
      'phase': 'battle',
      'round': 1,
      'timer': 0,
      'players': [
        {'id': 'p1', 'hp': 100, 'gold': 5, 'ready': true},
        {'id': 'p2', 'hp': 100, 'gold': 5, 'ready': true},
      ],
    });
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('skip-combat-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-combat-button')));
    await tester.pump();
    expect(find.text('รอคู่แข่ง…'), findsOneWidget);
    expect(transport.sent.last.event, GameActions.matchCombatDone);

    final opponentBoard = tester.getCenter(
      find.byKey(const ValueKey('battle-opponent-board')),
    );
    final versus = tester.getCenter(find.text('VS'));
    final playerBoard = tester.getCenter(
      find.byKey(const ValueKey('battle-player-board')),
    );
    final opponentLabel = tester.getCenter(find.text('คู่แข่ง').last);
    final playerLabel = tester.getCenter(find.text('คุณ').last);
    final skip = tester.getCenter(
      find.byKey(const ValueKey('skip-combat-button')),
    );
    expect(opponentBoard.dy, lessThan(versus.dy));
    expect(versus.dy, lessThan(playerBoard.dy));
    expect(opponentLabel.dy, closeTo(versus.dy, 1));
    expect(playerLabel.dy, closeTo(versus.dy, 1));
    expect(playerBoard.dy, lessThan(skip.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait battle uses the available viewport without scrolling',
      (tester) async {
    final transport = FakeWsTransport();
    final client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    addTearDown(client.dispose);
    final connected = client.connect();
    transport.serverConnect();
    await connected;
    _seed(transport, withUnits: true);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(665, 1200),
    );
    transport.emitFromServer(GameEvents.matchPhase, {
      'matchId': 'm1',
      'phase': 'battle',
      'round': 1,
      'timer': 0,
      'players': [
        {'id': 'p1', 'hp': 100, 'gold': 5, 'ready': true},
        {'id': 'p2', 'hp': 100, 'gold': 5, 'ready': true},
      ],
    });
    await tester.pump(const Duration(milliseconds: 600));

    final playerBoard = tester.getSize(
      find.byKey(const ValueKey('battle-player-board')),
    );
    final opponentBoard = tester.getSize(
      find.byKey(const ValueKey('battle-opponent-board')),
    );
    expect(playerBoard.width, greaterThan(360));
    expect(opponentBoard.width, playerBoard.width);
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _seed(FakeWsTransport transport, {bool withUnits = false}) {
  transport.emitFromServer(GameEvents.matchPhase, {
    'matchId': 'm1',
    'phase': 'shop_place',
    'round': 1,
    'timer': 40,
    'players': [
      {'id': 'p1', 'hp': 100, 'gold': 5, 'ready': false},
      {'id': 'p2', 'hp': 100, 'gold': 5, 'ready': false},
    ],
  });
  transport.emitFromServer(GameEvents.matchState, {
    'matchId': 'm1',
    'round': 1,
    'yourSide': 'p1',
    'roster': {
      'board': List<Object?>.filled(9, null),
      'bench': [
        if (withUnits)
          {
            'instanceId': 'unit-1',
            'unitId': 'fighter',
            'star': 0,
            'hp': 100,
            'maxHp': 100,
          }
        else
          null,
        ...List<Object?>.filled(7, null),
      ],
      'gold': 5,
      'hp': 100,
    },
    'opponent': {
      'gold': 5,
      'hp': 100,
      'boardSummary': List<Object?>.filled(9, null),
    },
    'readyCount': 0,
  });
  transport.emitFromServer(GameEvents.shopOffer, {
    'matchId': 'm1',
    'round': 1,
    'offers': [
      {'offerId': '1', 'unitId': 'fighter', 'star': 0},
      {'offerId': '2', 'unitId': 'healer', 'star': 0},
      {'offerId': '3', 'unitId': 'ranger', 'star': 0},
      {'offerId': '4', 'unitId': 'tank', 'star': 0},
      {'offerId': '5', 'unitId': 'fighter', 'star': 0},
    ],
  });
}
