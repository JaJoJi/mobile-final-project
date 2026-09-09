import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ws_transport.dart';

void main() {
  late FakeWsTransport transport;
  late WsClient client;

  setUp(() {
    transport = FakeWsTransport();
    client = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'jwt-token',
      transport: transport,
    );
  });

  tearDown(() => client.dispose());

  group('connect()', () {
    test('resolves once the server accepts the socket', () async {
      expect(client.state, WsConnectionState.disconnected);

      final future = client.connect();
      expect(transport.connectCalls, 1);
      expect(client.state, WsConnectionState.connecting);

      transport.serverConnect();
      await future; // does not throw

      expect(client.state, WsConnectionState.connected);
      expect(client.isConnected, isTrue);
    });

    test('rejects with WsAuthException on an auth game:error', () async {
      final future = client.connect();

      transport.emitFromServer(GameEvents.error, {
        'code': 'auth.expired',
        'message': 'jwt expired',
      });

      await expectLater(
        future,
        throwsA(
          isA<WsAuthException>().having((e) => e.code, 'code', 'auth.expired'),
        ),
      );
      expect(client.state, WsConnectionState.disconnected);
      expect(transport.disconnectCalls, greaterThanOrEqualTo(1));
    });

    test('a non-auth game:error does not reject the connect future', () async {
      final future = client.connect();

      transport.emitFromServer(GameEvents.error, {
        'code': 'shop.insufficient_gold',
      });
      transport.serverConnect();

      await future; // resolves normally
      expect(client.state, WsConnectionState.connected);
    });

    test('shares one pending future across concurrent callers', () async {
      final a = client.connect();
      final b = client.connect();
      expect(transport.connectCalls, 1);

      transport.serverConnect();
      await Future.wait([a, b]);
      expect(client.state, WsConnectionState.connected);
    });

    test('times out when asked and the server never answers', () {
      expect(
        client.connect(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('connection state', () {
    test(
        'goes reconnecting on an unexpected drop, back to connected on '
        'resume', () async {
      final states = <WsConnectionState>[];
      client.connectionState.listen(states.add);

      final future = client.connect();
      transport.serverConnect();
      await future;

      transport.serverDisconnect('transport close');
      await Future<void>.delayed(Duration.zero);
      expect(client.state, WsConnectionState.reconnecting);

      transport.serverReconnectAttempt();
      transport.serverConnect();
      await Future<void>.delayed(Duration.zero);

      expect(client.state, WsConnectionState.connected);
      expect(
        states,
        containsAllInOrder(<WsConnectionState>[
          WsConnectionState.connecting,
          WsConnectionState.connected,
          WsConnectionState.reconnecting,
          WsConnectionState.connected,
        ]),
      );
    });

    test('disconnect() stops reconnecting', () async {
      final future = client.connect();
      transport.serverConnect();
      await future;

      client.disconnect();
      expect(client.state, WsConnectionState.disconnected);
      expect(transport.disconnectCalls, 1);
    });
  });

  group('event streams', () {
    test('stream() fans one event out to multiple listeners', () async {
      final a = <int>[];
      final b = <int>[];
      client
          .stream(GameEvents.matchPhase)
          .listen((m) => a.add(m['round'] as int));
      client
          .stream(GameEvents.matchPhase)
          .listen((m) => b.add(m['round'] as int));

      transport.emitFromServer(GameEvents.matchPhase, {'round': 3});
      await Future<void>.delayed(Duration.zero);

      expect(a, [3]);
      expect(b, [3]);
    });

    test('streamAs() decodes payloads through the model factory', () async {
      final phases = <MatchPhaseEvent>[];
      client
          .streamAs(GameEvents.matchPhase, MatchPhaseEvent.fromJson)
          .listen(phases.add);

      transport.emitFromServer(GameEvents.matchPhase, {
        'matchId': 'm1',
        'phase': 'battle',
        'round': 2,
        'timer': 30,
        'players': [
          {'id': 'p1', 'hp': 90, 'gold': 5, 'ready': true},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(phases, hasLength(1));
      expect(phases.single.phase, GamePhase.battle);
      expect(phases.single.round, 2);
      expect(phases.single.players.single.hp, 90);
    });

    test('coerces a Map<dynamic,dynamic> payload to Map<String,dynamic>',
        () async {
      final seen = <Map<String, dynamic>>[];
      client.stream(GameEvents.matchState).listen(seen.add);

      transport.emitFromServer(GameEvents.matchState, <dynamic, dynamic>{
        'matchId': 'm1',
        'round': 1,
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.single['matchId'], 'm1');
    });

    test('ignores a non-map payload instead of throwing', () async {
      final seen = <Map<String, dynamic>>[];
      client.stream(GameEvents.matchState).listen(seen.add);

      transport.emitFromServer(GameEvents.matchState, 'not-a-map');
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });
  });

  group('errors stream', () {
    test('surfaces every game:error envelope', () async {
      final errors = <GameError>[];
      client.errors.listen(errors.add);

      transport.emitFromServer(GameEvents.error, {
        'code': 'match.round_mismatch',
        'clientActionId': 'abc',
      });
      await Future<void>.delayed(Duration.zero);

      expect(errors.single.code, 'match.round_mismatch');
      expect(errors.single.clientActionId, 'abc');
      expect(errors.single.isAuth, isFalse);
    });
  });

  group('emit()', () {
    test('forwards name + data to the transport', () async {
      client.emit(GameActions.matchmakingJoin);
      client.emit(GameActions.shopBuy, {'round': 1, 'offerIndex': 0});

      expect(transport.sent[0].event, 'game:matchmaking:join');
      expect(transport.sent[1].data, {'round': 1, 'offerIndex': 0});
    });

    test('throws after dispose', () {
      client.dispose();
      expect(() => client.emit(GameActions.matchReady), throwsStateError);
    });
  });
}
