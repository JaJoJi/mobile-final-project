import 'package:auto_chess_mobile/features/match/match_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

// `MatchScreen` is the last interim `PlaceholderScreen` (real UI lands in
// P0-FE-04). `/history` + `/history/:id` became real screens in P1-FE-01
// and are covered by test/features/history/.
void main() {
  testWidgets('MatchScreen placeholder renders the match id', (tester) async {
    await pumpScreen(tester, const MatchScreen(matchId: 'abc123'));
    expect(find.textContaining('abc123'), findsOneWidget);
    expect(find.text('กำลังพัฒนา'), findsOneWidget);
    expect(find.textContaining('P0-FE-04'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
