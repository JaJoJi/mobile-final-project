import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ws_transport.dart';

void main() {
  late FakeWsTransport transport;
  late WsClient client;
  late ProviderContainer container;

  setUp(() {
    transport = FakeWsTransport();
    client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'jwt',
      transport: transport,
    );
    container = ProviderContainer(
      overrides: [wsClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
  });

  test('wsConnectionStateProvider emits the current state first', () async {
    final sub = container.listen(wsConnectionStateProvider, (_, __) {});
    await container.pump();
    expect(sub.read().value, WsConnectionState.disconnected);
  });

  test('matchStateProvider decodes game:match:state payloads', () async {
    final sub = container.listen(matchStateProvider, (_, __) {});
    await container.pump();

    transport.emitFromServer(GameEvents.matchState, {
      'matchId': 'm1',
      'round': 2,
      'yourSide': 'p1',
      'roster': {
        'board': <Map<String, dynamic>>[],
        'bench': <Map<String, dynamic>>[],
        'gold': 5,
        'hp': 100,
      },
      'opponent': {
        'gold': 5,
        'hp': 100,
        'boardSummary': <Map<String, dynamic>>[],
      },
      'readyCount': 0,
    });
    await container.pump();

    final state = sub.read().value;
    expect(state, isNotNull);
    expect(state!.matchId, 'm1');
    expect(state.round, 2);
  });

  test('wsEventProvider family exposes an arbitrary event by name', () async {
    final sub = container.listen(
      wsEventProvider(GameEvents.matchPhase),
      (_, __) {},
    );
    await container.pump();

    transport.emitFromServer(GameEvents.matchPhase, {'round': 9});
    await container.pump();

    expect(sub.read().value?['round'], 9);
  });

  test('gameErrorProvider surfaces game:error envelopes', () async {
    final sub = container.listen(gameErrorProvider, (_, __) {});
    await container.pump();

    transport.emitFromServer(GameEvents.error, {'code': 'shop.refresh_used'});
    await container.pump();

    expect(sub.read().value?.code, 'shop.refresh_used');
  });
}
