import 'package:auto_chess_mobile/features/match/match_found_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'profiles approach, collide, rebound and finish before navigation',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Stack(
              children: [
                MatchFoundTransition(
                  leftName: 'Alice',
                  rightName: 'Bob',
                  onCompleted: () => completed = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final left = find.byKey(const ValueKey('left-fighter-icon'));
    final right = find.byKey(const ValueKey('right-fighter-icon'));
    double gap() => tester.getCenter(right).dx - tester.getCenter(left).dx;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final approaching = gap();
    await tester.pump(const Duration(milliseconds: 200));
    final contact = gap();
    expect(contact, lessThan(approaching));
    expect(contact, closeTo(82, 1));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(gap(), greaterThan(contact + 60));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(completed, isTrue);
    expect(find.byIcon(Icons.directions_run_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
