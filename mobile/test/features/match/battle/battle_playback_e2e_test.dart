import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/match/battle/battle_view.dart';
import 'package:auto_chess_mobile/features/match/match_screen.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/ws/fake_ws_transport.dart';
import '../../_util.dart';

/// Snapshot of both units, reused on every event so `deriveUnitStates`
/// always has a board to render.
List<Map<String, Object?>> _snapshot({int targetHp = 100}) => [
      {
        'instanceId': 'a1',
        'unitId': 'fighter',
        'star': 0,
        'hp': 100,
        'maxHp': 100,
        'slot': 0,
        'side': 'p1',
        'alive': true,
      },
      {
        'instanceId': 'b1',
        'unitId': 'fighter',
        'star': 0,
        'hp': targetHp,
        'maxHp': 100,
        'slot': 4,
        'side': 'p2',
        'alive': targetHp > 0,
      },
    ];

/// One melee attack by p1 slot 0 against p2 slot 4.
Map<String, Object?> _attack(int tick, int targetHp) => {
      'type': 'attack',
      'cycle': 1,
      'tick': tick,
      'attacker': 'a1',
      'target': 'b1',
      'damage': 10,
      'targetHpAfter': targetHp,
      'attackerSide': 'p1',
      'attackerSlot': 0,
      'attackerUnitId': 'fighter',
      'targetSide': 'p2',
      'targetSlot': 4,
      'targetUnitId': 'fighter',
      'unitStates': _snapshot(targetHp: targetHp),
    };

void _seedMatch(FakeWsTransport transport) {
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
      'board': [
        {
          'instanceId': 'a1',
          'unitId': 'fighter',
          'star': 0,
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
      'boardSummary': [
        ...List<Object?>.filled(4, null),
        {'unitId': 'fighter', 'star': 0},
        ...List<Object?>.filled(4, null),
      ],
    },
    'readyCount': 0,
  });
}

/// Translation currently applied to the attacker's tile (p1 slot 0 is the
/// first tile of the player's board).
Offset _attackerTileOffset(WidgetTester tester) {
  final tile = find
      .descendant(
        of: find.byKey(const ValueKey('battle-player-board')),
        matching: find.byType(BattleTile),
      )
      .first;
  final transform = tester.widget<Transform>(
    find.descendant(of: tile, matching: find.byType(Transform)).first,
  );
  final t = transform.transform.getTranslation();
  return Offset(t.x, t.y);
}

void main() {
  testWidgets('combat playback advances and the melee attacker visibly moves',
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
    _seedMatch(transport);

    await pumpScreen(
      tester,
      const MatchScreen(matchId: 'm1'),
      overrides: [wsClientProvider.overrideWithValue(client)],
      surfaceSize: const Size(390, 844),
    );

    // Enter the battle phase, then deliver the combat batch.
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
    await tester.pump();

    transport.emitFromServer(GameEvents.combatEvents, {
      'matchId': 'm1',
      'round': 1,
      'cycleCount': 1,
      'endedAt': 0,
      'events': [
        _attack(1, 90),
        _attack(2, 80),
        _attack(3, 70),
        _attack(4, 60),
      ],
    });
    // Let the post-frame replay / stream listener deliver the batch.
    await tester.pump();
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'delivering the batch must not throw (setState during mount)',
    );

    // The batch must actually be loaded, not silently dropped.
    expect(
      find.textContaining('batch loaded'),
      findsOneWidget,
      reason: 'BattleView should report a loaded batch',
    );

    // Walk the playhead forward and record what the attacker tile does.
    final offsets = <Offset>[];
    final summaries = <String>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      offsets.add(_attackerTileOffset(tester));
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('battle-batch-summary')))
          .data!;
      summaries.add(text);
    }

    // 1. Playback must progress past 0%.
    expect(
      summaries.any((s) => !s.contains('playhead 0%')),
      isTrue,
      reason: 'playhead never advanced past 0%: ${summaries.first} '
          '... ${summaries.last}',
    );

    // 2. The attacker tile must actually move at some point.
    final moved = offsets.any((o) => o.dx.abs() > 0.5 || o.dy.abs() > 0.5);
    expect(
      moved,
      isTrue,
      reason: 'attacker tile never translated; offsets were $offsets',
    );
  });
}
