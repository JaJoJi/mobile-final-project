import 'package:auto_chess_mobile/features/lobby/lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

// NOTE: LobbyScreen is the interim landing screen (the old connectivity
// smoke screen, renamed). P0-FE-03 replaces it with the real find-match
// lobby, at which point this test is rewritten. It still predates the
// design system, so no a11y-guideline sweep here yet.
void main() {
  testWidgets('renders the app bar, profile + logout actions, and its buttons',
      (tester) async {
    await pumpScreen(tester, const LobbyScreen());

    expect(find.text('Auto Chess — Connect'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.text('GET /health + /user/me'), findsOneWidget);
    expect(
      find.textContaining('Ping 12 times'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no identity card until the checks run', (tester) async {
    await pumpScreen(tester, const LobbyScreen());
    expect(find.text('Signed in'), findsNothing);
  });
}
