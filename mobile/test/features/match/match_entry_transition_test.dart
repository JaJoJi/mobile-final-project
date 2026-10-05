import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/match/match_entry_transition.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/ws/fake_ws_transport.dart';
import 'match_entry_fixture.dart';

void main() {
  for (final lateShop in [false, true]) {
    testWidgets('entry waits for animation and data (late shop: $lateShop)',
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
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await warmEntryArt(tester);
      seedEntrySnapshot(transport, 'entry', includeShop: !lateShop);
      transport.emitFromServer(GameEvents.matchPhase, {
        'matchId': 'entry',
        'phase': 'shop_place',
        'round': 1,
        'timer': 40,
        'players': <Map<String, dynamic>>[],
      });
      var readyCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wsClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            home: Stack(
              children: [
                const SizedBox.expand(),
                MatchEntryTransition(
                  matchId: 'entry',
                  leftName: 'Alice',
                  rightName: 'Bob',
                  onReady: () => readyCalls++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(readyCalls, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      if (lateShop) {
        expect(readyCalls, 0);
        expect(
          find.byKey(const ValueKey('match-found-transition')),
          findsOneWidget,
        );
        seedEntrySnapshot(transport, 'entry');
        await tester.pump();
        await tester.pump();
      }
      expect(readyCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(readyCalls, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
