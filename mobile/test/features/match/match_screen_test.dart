import 'package:auto_chess_mobile/core/theme/app_spacing.dart';
import 'package:auto_chess_mobile/core/widgets/game_art_frame.dart';
import 'package:auto_chess_mobile/core/widgets/game_asset_button.dart';
import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/match/board/stone_board_tile.dart';
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
    final shopWidths = List.generate(
      5,
      (index) => tester.getSize(find.byKey(ValueKey('shop-$index'))).width,
    );
    expect(shopWidths.toSet(), hasLength(1));
    final firstShopCard = find.byKey(const ValueKey('shop-0'));
    final firstShopFrame = find.descendant(
      of: firstShopCard,
      matching: find.byType(GameArtFrame),
    );
    expect(
      tester.getSize(firstShopFrame).width,
      closeTo(tester.getSize(firstShopCard).width, 0.1),
    );
    final firstShopPrice = find.descendant(
      of: firstShopCard,
      matching: find.text('1'),
    );
    expect(
      tester.getBottomRight(firstShopPrice).dy,
      lessThan(tester.getBottomRight(firstShopCard).dy),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shop-panel')),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    expect(find.text('พร้อม (0/2)'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('ร้านค้า'), findsOneWidget);
    expect(find.text('Fighter'), findsWidgets);
    expect(find.text('Healer'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-hp-value')), findsOneWidget);
    expect(find.byKey(const ValueKey('opponent-hp-value')), findsOneWidget);
    expect(find.byKey(const ValueKey('hud-timer-medallion')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-bar-frame')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('ready-button'))).height,
      greaterThanOrEqualTo(48),
    );
    final frameAssets = tester
        .widgetList<GameArtFrame>(find.byType(GameArtFrame))
        .map((frame) => frame.frameAsset)
        .toSet();
    final buttonAssets = tester
        .widgetList<GameAssetButton>(find.byType(GameAssetButton))
        .map((button) => button.frameAsset)
        .toSet();
    expect(frameAssets, isNot(contains(GameUiAssets.actionBarFrame)));
    expect(frameAssets, isNot(contains(GameUiAssets.hudPlayerFrame)));
    expect(frameAssets, isNot(contains(GameUiAssets.hudEnemyFrame)));
    expect(buttonAssets, contains(GameUiAssets.readyButtonFrame));
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

    await tester.tap(find.byKey(const ValueKey('ready-button')));
    await tester.pump();
    expect(find.text('ยกเลิกพร้อม (1/2)'), findsOneWidget);
    expect(
      tester
          .widget<GameAssetButton>(
            find.byKey(const ValueKey('ready-button')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('planning-board-dimmer')),
          )
          .opacity,
      0.68,
    );
    expect(transport.sent.last.event, GameActions.matchReady);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HUD tweens HP values instead of replacing them instantly',
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

    transport.emitFromServer(GameEvents.matchState, {
      'matchId': 'm1',
      'round': 1,
      'yourSide': 'p1',
      'roster': {
        'board': List<Object?>.filled(9, null),
        'bench': List<Object?>.filled(8, null),
        'gold': 5,
        'hp': 60,
      },
      'opponent': {
        'gold': 5,
        'hp': 75,
        'boardSummary': List<Object?>.filled(9, null),
      },
      'readyCount': 0,
    });
    await tester.pump();

    expect(find.text('100'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 100));
    final playerMid = int.parse(
      tester.widget<Text>(find.byKey(const ValueKey('player-hp-value'))).data!,
    );
    final opponentMid = int.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('opponent-hp-value')))
          .data!,
    );
    expect(playerMid, inExclusiveRange(60, 100));
    expect(opponentMid, inExclusiveRange(75, 100));

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('60'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
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

    await tester.longPress(firstShopCard);
    await tester.pump();
    expect(tester.getSize(activeFace), cardSize);

    await tester.tap(firstShopCard);
    await tester.pump(const Duration(milliseconds: 160));

    expect(tester.getRect(boardFinder), before);
    expect(find.text('ซื้อแล้ว'), findsNothing);
    final reservePulse = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('reserve-purchase-pulse')),
    );
    expect(
      (reservePulse.decoration as BoxDecoration).boxShadow,
      isNotEmpty,
    );
    final purchasedFace = find.descendant(
      of: firstShopCard,
      matching: find.byType(AspectRatio),
    );
    expect(tester.getSize(purchasedFace), cardSize);
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('ซื้อแล้ว'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('gold-value'))).data,
      '4',
    );
    expect(tester.getRect(boardFinder), before);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('กำลังบันทึกสถานะพร้อม'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unaffordable shop card shakes without sending a buy action',
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
    _seed(transport, gold: 0);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(430, 932),
    );
    await tester.pump();

    final firstShopCard = find.byKey(const ValueKey('shop-0'));
    final feedback = find.descendant(
      of: firstShopCard,
      matching: find.byKey(const ValueKey('shop-card-feedback')),
    );
    expect(
      tester.widget<Transform>(feedback).transform.getTranslation().x,
      0,
    );

    await tester.tap(firstShopCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(
      tester.widget<Transform>(feedback).transform.getTranslation().x.abs(),
      greaterThan(1),
    );
    expect(
      transport.sent.where((event) => event.event == GameActions.shopBuy),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('planning micro-interactions respect reduced motion',
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
      const MediaQuery(
        data: MediaQueryData(
          size: Size(430, 932),
          disableAnimations: true,
        ),
        child: MatchScreen(matchId: 'm1'),
      ),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(430, 932),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('shop-0')));
    await tester.pump();

    expect(find.text('ซื้อแล้ว'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging from the bench keeps the stone board stable and places',
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
      surfaceSize: const Size(430, 932),
    );
    await tester.pump();

    final grid = find.byKey(const ValueKey('planning-board-grid'));
    final boardSlot = find.byKey(const ValueKey('board-0'));
    final benchSlot = find.byKey(const ValueKey('bench-0'));
    final gridBefore = tester.getRect(grid);
    final tileImage = tester.widget<Image>(
      find.descendant(of: boardSlot, matching: find.byType(Image)).first,
    );
    expect(
      (tileImage.image as AssetImage).assetName,
      'assets/images/board/board_tile_stone_01.png',
    );

    await tester.dragFrom(
      tester.getCenter(benchSlot),
      tester.getCenter(boardSlot) - tester.getCenter(benchSlot),
    );
    await tester.pump();

    expect(tester.getRect(grid), gridBefore);
    expect(transport.sent.last.event, GameActions.matchPlace);
    final payload = transport.sent.last.data! as Map<String, dynamic>;
    expect(payload['target'], 'board');
    expect(payload['slot'], 0);
    await tester.pump(const Duration(milliseconds: 40));
    final stone = tester.widget<StoneBoardTile>(
      find.descendant(of: boardSlot, matching: find.byType(StoneBoardTile)),
    );
    expect(stone.effect, isNotNull);
    expect(stone.effect!.value, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 520));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a star upgrade shows the golden fuse treatment', (tester) async {
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

    void emitBoardUnit(int star) {
      transport.emitFromServer(GameEvents.matchState, {
        'matchId': 'm1',
        'round': 1,
        'yourSide': 'p1',
        'roster': {
          'board': [
            {
              'instanceId': 'fighter-1',
              'unitId': 'fighter',
              'star': star,
              'hp': 100,
              'maxHp': 100,
            },
            ...List<Object?>.filled(8, null),
          ],
          'bench': List<Object?>.filled(8, null),
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
    }

    emitBoardUnit(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 520));
    emitBoardUnit(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final boardSlot = find.byKey(const ValueKey('board-0'));
    final stone = tester.widget<StoneBoardTile>(
      find.descendant(of: boardSlot, matching: find.byType(StoneBoardTile)),
    );
    expect(stone.fuseEffect, isTrue);
    expect(
      find.descendant(of: boardSlot, matching: find.byIcon(Icons.star)),
      findsAtLeastNWidgets(3),
    );
    await tester.pump(const Duration(milliseconds: 520));
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
    expect(find.byKey(const ValueKey('result-win')), findsOneWidget);
    expect(
      tester
          .widgetList<GameArtFrame>(find.byType(GameArtFrame))
          .map((frame) => frame.frameAsset),
      contains(GameUiAssets.resultPanelFrame),
    );
    expect(find.text('ทีมสุดท้าย'), findsOneWidget);
    expect(find.text('HP สุดท้าย 72 / 100'), findsOneWidget);
    expect(find.text('เล่นอีกครั้ง'), findsOneWidget);
    expect(find.text('กลับหน้าหลัก'), findsOneWidget);
    expect(
      tester.getCenter(find.text('กลับหน้าหลัก')).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('back-to-lobby-button'))).dy,
        0.1,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('result-trophy'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('result-win'))).dy +
            AppSpacing.xl,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('match result uses the lose treatment for the defeated player',
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
    transport.emitFromServer(GameEvents.matchEnd, {
      'matchId': 'm1',
      'winnerId': 'p2',
      'reason': 'hp_zero',
      'final': {
        'p1': {'hp': 0, 'gold': 1},
        'p2': {'hp': 54, 'gold': 3},
      },
    });
    await tester.pump();

    expect(find.byKey(const ValueKey('result-lose')), findsOneWidget);
    expect(find.text('แพ้'), findsOneWidget);
    expect(find.text('HP สุดท้าย 0 / 100'), findsOneWidget);
    expect(
      tester.getSize(find.text('เล่นอีกครั้ง')).height,
      lessThanOrEqualTo(
        tester.getSize(find.byType(GameAssetButton).first).height,
      ),
    );
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
    final damageLane = tester.getSize(
      find.byKey(const ValueKey('combat-damage-lane')),
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
    expect(damageLane.height, AppSpacing.xxl);
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

void _seed(
  FakeWsTransport transport, {
  bool withUnits = false,
  int gold = 5,
}) {
  transport.emitFromServer(GameEvents.matchPhase, {
    'matchId': 'm1',
    'phase': 'shop_place',
    'round': 1,
    'timer': 40,
    'players': [
      {'id': 'p1', 'hp': 100, 'gold': gold, 'ready': false},
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
      'gold': gold,
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
