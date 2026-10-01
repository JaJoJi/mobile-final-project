import 'package:auto_chess_mobile/core/widgets/health_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('unit HP track is grey with a black outline in $brightness',
        (tester) async {
      await pumpThemed(
        tester,
        const HealthBar(
          current: 60,
          max: 100,
          width: 120,
          compactUnitStyle: true,
        ),
        brightness: brightness,
      );
      final track = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('unit-health-bar-track')),
      );
      expect(
        (track.decoration as BoxDecoration).color,
        const Color(0xFF424242),
      );
      final frame = tester.widget<Container>(
        find.byKey(const ValueKey('unit-health-bar-frame')),
      );
      final border =
          (frame.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(border.top.color, Colors.black);
      expect(border.top.width, 1);
      expect(find.text('60 / 100'), findsOneWidget);
    });
  }

  testWidgets('player HP bar uses the same grey track and black outline',
      (tester) async {
    await pumpThemed(
      tester,
      const HealthBar(current: 85, max: 100, width: 200),
    );
    expect(find.byKey(const ValueKey('unit-health-bar-frame')), findsNothing);
    expect(find.byKey(const ValueKey('unit-health-bar-track')), findsNothing);
    final frame = tester.widget<Container>(
      find.byKey(const ValueKey('health-bar-frame')),
    );
    final border =
        (frame.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(border.top.color, Colors.black);
    expect(border.top.width, 1);
    final track = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('health-bar-track')),
    );
    expect(
      (track.decoration as BoxDecoration).color,
      const Color(0xFF424242),
    );
  });

  testWidgets('low unit HP keeps the full requested bar width', (tester) async {
    await pumpThemed(
      tester,
      const HealthBar(
        current: 10,
        max: 100,
        width: 120,
        showText: false,
        compactUnitStyle: true,
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('unit-health-bar-frame'))).width,
      120,
    );
  });
}
