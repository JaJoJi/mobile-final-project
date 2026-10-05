import 'package:auto_chess_mobile/features/history/match_detail_screen.dart';
import 'package:auto_chess_mobile/features/history/round_row.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_test_util.dart';

Map<String, dynamic> _detail({
  List<Map<String, dynamic>> rounds = const [],
  String? winner = 'alice',
  String? winnerId = 'a',
}) =>
    {
      'matchId': 'm1',
      'players': [
        {'id': 'a', 'username': 'alice'},
        {'id': 'b', 'username': 'bob'},
      ],
      'winner': winner,
      'winnerId': winnerId,
      'status': 'finished',
      'createdAt': '2026-03-07T14:02:00.000Z',
      'finishedAt': '2026-03-07T14:06:12.000Z',
      'rounds': rounds,
    };

ResponseBody _response(RequestOptions request, Map<String, dynamic> detail) =>
    request.path == '/user/me'
        ? jsonBody({'id': 'a', 'username': 'alice', 'rating': 1000})
        : jsonBody(detail);

void main() {
  testWidgets('renders the matchup, result chip and round rows',
      (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter(
        (o) => _response(
          o,
          _detail(
            rounds: [
              {
                'roundNumber': 1,
                'events': [
                  {'type': 'battle_end', 'winner': 'p1'},
                ],
              },
              {
                'roundNumber': 2,
                'events': [
                  {'type': 'attack'},
                  {'type': 'battle_end', 'winner': 'p2'},
                ],
              },
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsWidgets);
    expect(find.text('bob'), findsWidgets);
    expect(find.text('alice ชนะ'), findsWidgets);
    expect(find.byType(RoundRow), findsNWidgets(2));
    expect(find.textContaining('เหตุการณ์'), findsNothing);
    expect(
      find.byKey(const ValueKey('player-hub-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('no rounds → the "no data" note, no crash', (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter((o) => _response(o, _detail())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีข้อมูลรอบ'), findsOneWidget);
    expect(find.byType(RoundRow), findsNothing);
  });

  testWidgets('no overflow on a compact mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter(
        (o) => _response(
          o,
          _detail(
            rounds: [
              {
                'roundNumber': 1,
                'events': [
                  {'type': 'battle_end', 'winner': 'p1'},
                ],
              },
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('player-hub-navigation')), findsOneWidget);
  });

  testWidgets('shows a loss from the signed-in player perspective',
      (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter(
        (o) => _response(
          o,
          _detail(winner: 'bob', winnerId: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('แพ้ให้ bob'), findsOneWidget);
  });

  testWidgets('error shows a retry', (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter(
        (o) => o.path == '/user/me'
            ? jsonBody({'id': 'a', 'username': 'alice', 'rating': 1000})
            : jsonBody(const {'message': 'boom'}, 500),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });
}
