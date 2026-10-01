import 'package:auto_chess_mobile/features/history/history_list_screen.dart';
import 'package:auto_chess_mobile/features/history/match_list_item.dart';
import 'package:auto_chess_mobile/features/lobby/player_hub_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_test_util.dart';

Finder _rowWord(String label) => find.descendant(
      of: find.byType(MatchListItem),
      matching: find.text(label),
    );

List<Map<String, dynamic>> _rows() => [
      {
        'matchId': 'm-win',
        'opponent': {'id': 'u2', 'username': 'bob'},
        'winner': 'self',
        'status': 'finished',
        'rounds': 7,
        'createdAt': DateTime.now()
            .subtract(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
        'duration': 252,
      },
      {
        'matchId': 'm-loss',
        'opponent': {'id': 'u3', 'username': 'carol'},
        'winner': 'opponent',
        'status': 'finished',
        'rounds': 5,
        'createdAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'duration': 90,
      },
    ];

void main() {
  testWidgets('renders a row per match with the result word', (tester) async {
    await pumpHistory(
      tester,
      const HistoryListScreen(),
      FakeAdapter((o) => jsonBody(_rows())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MatchListItem), findsNWidgets(2));
    expect(_rowWord('ชนะ'), findsOneWidget);
    expect(_rowWord('แพ้'), findsOneWidget);
    expect(find.textContaining('bob'), findsOneWidget);
    expect(find.text('ประวัติการแข่งขัน'), findsOneWidget);
    expect(find.byType(PlayerHubNavigation), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('empty response shows the EmptyView CTA', (tester) async {
    await pumpHistory(
      tester,
      const HistoryListScreen(),
      FakeAdapter((o) => jsonBody(const [])),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีประวัติแมตช์'), findsOneWidget);
    expect(find.text('ค้นหาคู่แข่ง'), findsOneWidget);
  });

  testWidgets('error shows a retry', (tester) async {
    await pumpHistory(
      tester,
      const HistoryListScreen(),
      FakeAdapter((o) => jsonBody(const {'message': 'boom'}, 500)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('the filter menu can show losses only', (tester) async {
    await pumpHistory(
      tester,
      const HistoryListScreen(),
      FakeAdapter((o) => jsonBody(_rows())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('history-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-filter-losses')));
    await tester.pumpAndSettle();

    expect(find.byType(MatchListItem), findsOneWidget);
    expect(find.textContaining('carol'), findsOneWidget);
  });

  testWidgets('tapping a row navigates to the detail route', (tester) async {
    await pumpHistory(
      tester,
      const HistoryListScreen(),
      FakeAdapter((o) => jsonBody(_rows())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MatchListItem).first);
    await tester.pumpAndSettle();
    expect(find.text('stub:detail'), findsOneWidget);
  });
}
