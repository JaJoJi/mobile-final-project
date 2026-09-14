import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/features/match/match_controller.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/ws/fake_ws_transport.dart';

void main() {
  late FakeWsTransport transport;
  late WsClient client;
  late MatchController controller;

  setUp(() async {
    transport = FakeWsTransport();
    client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    _seedMatch(transport);
    controller = MatchController(matchId: 'm1', client: client);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    controller.dispose();
    client.dispose();
  });

  test('replays initial phase, state and shop sent before route mounted', () {
    expect(controller.state.phase?.round, 1);
    expect(controller.state.match?.roster.gold, 5);
    expect(controller.state.shop?.offers, hasLength(5));
  });

  test('buy updates gold and bench optimistically then rolls back on error',
      () async {
    var uiUpdates = 0;
    final removeListener = controller.addListener(
      (_) => uiUpdates++,
      fireImmediately: false,
    );
    controller.buy(0);

    expect(uiUpdates, 1);
    removeListener();
    expect(controller.state.match?.roster.gold, 4);
    expect(controller.state.match?.roster.bench.first?.unitId, UnitId.fighter);
    expect(controller.state.shop?.offers.first, isNull);
    final sent = transport.sent.last;
    expect(sent.event, GameActions.shopBuy);
    final payload = sent.data! as Map<String, dynamic>;
    expect(payload['offerIndex'], 0);
    expect(
      payload['clientActionId'],
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')),
    );

    transport.emitFromServer(GameEvents.error, {
      'code': 'shop.insufficient_gold',
      'clientActionId': payload['clientActionId'],
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.match?.roster.gold, 5);
    expect(controller.state.match?.roster.bench.first, isNull);
    expect(controller.state.shop?.offers.first, isNotNull);
    expect(controller.state.errorMessage, 'ทองไม่พอ');
  });

  test('tap-select placement maps board slot row-major and emits place',
      () async {
    transport.emitFromServer(
      GameEvents.matchState,
      _matchState(
        bench: [
          _unit('u1', 'tank'),
          ...List<Object?>.filled(7, null),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.select(RosterArea.bench, 0);
    var uiUpdates = 0;
    final removeListener = controller.addListener(
      (_) => uiUpdates++,
      fireImmediately: false,
    );
    controller.select(RosterArea.board, 4);

    expect(uiUpdates, 1);
    removeListener();
    final payload = transport.sent.last.data! as Map<String, dynamic>;
    expect(transport.sent.last.event, GameActions.matchPlace);
    expect(payload['target'], 'board');
    expect(payload['slot'], 4);
    expect(BoardPosition.fromSlot(4), const BoardPosition(row: 1, col: 1));
  });

  test('dropping a matching unit onto another emits an exact fuse pair',
      () async {
    transport.emitFromServer(
      GameEvents.matchState,
      _matchState(
        bench: [
          _unit('fighter-source', 'fighter'),
          _unit('fighter-target', 'fighter'),
          ...List<Object?>.filled(6, null),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller.place(
      RosterArea.bench,
      1,
      const UnitSelection(RosterArea.bench, 0),
    );

    expect(transport.sent.last.event, GameActions.shopFuse);
    final payload = transport.sent.last.data! as Map<String, dynamic>;
    expect(payload['unitId'], 'fighter');
    expect(payload['sourceInstanceId'], 'fighter-source');
    expect(payload['targetInstanceId'], 'fighter-target');
  });

  test('ready can be submitted and cancelled before both players are ready',
      () async {
    controller.toggleReady();

    expect(controller.state.readySubmitted, isTrue);
    expect(controller.state.match?.readyCount, 1);
    expect(transport.sent.last.event, GameActions.matchReady);
    expect(
      (transport.sent.last.data! as Map<String, dynamic>)['ready'],
      isTrue,
    );

    transport.emitFromServer(GameEvents.matchState, _matchState(readyCount: 1));
    await Future<void>.delayed(Duration.zero);
    controller.toggleReady();

    expect(controller.state.readySubmitted, isFalse);
    expect(controller.state.match?.readyCount, 0);
    expect(
      (transport.sent.last.data! as Map<String, dynamic>)['ready'],
      isFalse,
    );
  });

  test('battle skip sends combat_done once and waits for the other player',
      () async {
    transport.emitFromServer(GameEvents.matchPhase, {
      'matchId': 'm1',
      'phase': 'battle',
      'round': 1,
      'timer': 0,
      'players': [
        {'id': 'p1-user', 'hp': 100, 'gold': 5, 'ready': true},
        {'id': 'p2-user', 'hp': 100, 'gold': 5, 'ready': true},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    controller.skipCombat();
    controller.skipCombat();

    expect(controller.state.combatDoneSubmitted, isTrue);
    expect(
      transport.sent.where(
        (event) => event.event == GameActions.matchCombatDone,
      ),
      hasLength(1),
    );
    final payload = transport.sent.last.data! as Map<String, dynamic>;
    expect(payload['matchId'], 'm1');
    expect(payload['round'], 1);
  });
}

void _seedMatch(FakeWsTransport transport) {
  transport.emitFromServer(GameEvents.matchPhase, {
    'matchId': 'm1',
    'phase': 'shop_place',
    'round': 1,
    'timer': 40,
    'players': [
      {'id': 'p1-user', 'hp': 100, 'gold': 5, 'ready': false},
      {'id': 'p2-user', 'hp': 100, 'gold': 5, 'ready': false},
    ],
  });
  transport.emitFromServer(GameEvents.matchState, _matchState());
  transport.emitFromServer(GameEvents.shopOffer, {
    'matchId': 'm1',
    'round': 1,
    'offers': [
      {'offerId': 'o1', 'unitId': 'fighter', 'star': 0},
      {'offerId': 'o2', 'unitId': 'healer', 'star': 0},
      {'offerId': 'o3', 'unitId': 'ranger', 'star': 0},
      {'offerId': 'o4', 'unitId': 'tank', 'star': 0},
      {'offerId': 'o5', 'unitId': 'fighter', 'star': 0},
    ],
  });
}

Map<String, dynamic> _matchState({
  List<Object?>? bench,
  int readyCount = 0,
}) =>
    {
      'matchId': 'm1',
      'round': 1,
      'yourSide': 'p1',
      'roster': {
        'board': List<Object?>.filled(9, null),
        'bench': bench ?? List<Object?>.filled(8, null),
        'gold': 5,
        'hp': 100,
      },
      'opponent': {
        'gold': 5,
        'hp': 100,
        'boardSummary': List<Object?>.filled(9, null),
      },
      'readyCount': readyCount,
    };

Map<String, dynamic> _unit(String id, String unitId) => {
      'instanceId': id,
      'unitId': unitId,
      'star': 0,
      'hp': 150,
      'maxHp': 150,
    };
