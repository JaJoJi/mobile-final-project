import 'package:auto_chess_mobile/core/widgets/game_art_frame.dart';
import 'package:auto_chess_mobile/core/widgets/unit_avatar.dart';
import 'package:auto_chess_mobile/shared/models/game_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/ws/fake_ws_transport.dart';

Future<void> warmEntryArt(WidgetTester tester) async {
  final context = tester.element(find.byType(Navigator).first);
  await tester.runAsync(
    () => Future.wait(
      [
        for (final path in {
          ...GameUiAssets.hud,
          ...GameBackgroundAssets.all,
          ...allUnitArtPaths,
        })
          precacheImage(AssetImage(path), context),
      ],
    ),
  );
}

void seedEntrySnapshot(
  FakeWsTransport transport,
  String matchId, {
  bool includeShop = true,
}) {
  transport.emitFromServer(GameEvents.matchState, {
    'matchId': matchId,
    'round': 1,
    'yourSide': 'p1',
    'roster': {
      'username': 'player1',
      'board': List<Object?>.filled(9, null),
      'bench': List<Object?>.filled(8, null),
      'gold': 5,
      'hp': 100,
    },
    'opponent': {
      'username': 'player2',
      'gold': 5,
      'hp': 100,
      'boardSummary': List<Object?>.filled(9, null),
    },
    'readyCount': 0,
  });
  if (!includeShop) return;
  transport.emitFromServer(GameEvents.shopOffer, {
    'matchId': matchId,
    'round': 1,
    'offers': <Map<String, dynamic>>[],
  });
}
