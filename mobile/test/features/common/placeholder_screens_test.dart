import 'package:auto_chess_mobile/features/history/history_detail_screen.dart';
import 'package:auto_chess_mobile/features/history/history_list_screen.dart';
import 'package:auto_chess_mobile/features/match/match_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

// MatchScreen / HistoryListScreen / MatchDetailScreen are interim
// PlaceholderScreens until P0-FE-04 / P1-FE-01. These smoke tests just
// guarantee they render and name their owning ticket.
void main() {
  testWidgets('MatchScreen placeholder renders the match id', (tester) async {
    await pumpScreen(tester, const MatchScreen(matchId: 'abc123'));
    expect(find.textContaining('abc123'), findsOneWidget);
    expect(find.text('กำลังพัฒนา'), findsOneWidget);
    expect(find.textContaining('P0-FE-04'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistoryListScreen placeholder renders', (tester) async {
    await pumpScreen(tester, const HistoryListScreen());
    expect(find.text('ประวัติแมตช์'), findsOneWidget);
    expect(find.text('กำลังพัฒนา'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MatchDetailScreen placeholder renders the match id',
      (tester) async {
    await pumpScreen(tester, const MatchDetailScreen(matchId: 'm-42'));
    expect(find.textContaining('m-42'), findsOneWidget);
    expect(find.text('กำลังพัฒนา'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
