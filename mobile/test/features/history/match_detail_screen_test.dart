import 'package:auto_chess_mobile/features/history/match_detail_screen.dart';
import 'package:auto_chess_mobile/features/history/round_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_test_util.dart';

Map<String, dynamic> _detail({List<Map<String, dynamic>> rounds = const []}) =>
    {
      'matchId': 'm1',
      'players': [
        {'id': 'a', 'username': 'alice'},
        {'id': 'b', 'username': 'bob'},
      ],
      'winner': 'alice',
      'winnerId': 'a',
      'status': 'finished',
      'createdAt': '2026-03-07T14:02:00.000Z',
      'finishedAt': '2026-03-07T14:06:12.000Z',
      'rounds': rounds,
    };

void main() {
  testWidgets('renders the matchup, result chip and round rows',
      (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter(
        (o) => jsonBody(
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

    expect(find.textContaining('alice พบ bob'), findsOneWidget);
    expect(find.textContaining('ผู้ชนะ: alice'), findsOneWidget);
    expect(find.byType(RoundRow), findsNWidgets(2));
  });

  testWidgets('no rounds → the "no data" note, no crash', (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter((o) => jsonBody(_detail())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีข้อมูลรอบ'), findsOneWidget);
    expect(find.byType(RoundRow), findsNothing);
  });

  testWidgets('error shows a retry', (tester) async {
    await pumpHistory(
      tester,
      const MatchDetailScreen(matchId: 'm1'),
      FakeAdapter((o) => jsonBody(const {'message': 'boom'}, 500)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });
}
