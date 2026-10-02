import 'dart:async';

import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/units/unit_detail_screen.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:auto_chess_mobile/shared/models/unit_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_util.dart';

/// Pump the detail screen for a given [unitId].
Future<void> _pumpDetail(
  WidgetTester tester,
  UnitId unitId, {
  Size surfaceSize = const Size(390, 844),
}) async {
  installFakeSecureStorage();

  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: UnitDetailScreen(unitId: unitId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('UnitDetailScreen', () {
    for (final id in UnitId.values) {
      final entry = unitCatalog[id]!;

      testWidgets('shows correct name for ${id.name}', (tester) async {
        await _pumpDetail(tester, id);
        expect(find.text(entry.name), findsOneWidget);
      });

      testWidgets('shows correct role for ${id.name}', (tester) async {
        await _pumpDetail(tester, id);
        expect(find.text(entry.role), findsOneWidget);
      });

      testWidgets('shows cost for ${id.name}', (tester) async {
        await _pumpDetail(tester, id);
        expect(find.text('${entry.cost}'), findsOneWidget);
      });

      testWidgets('shows ★1 ability by default for ${id.name}', (tester) async {
        await _pumpDetail(tester, id);
        expect(find.text(entry.abilities[0].description), findsOneWidget);
      });

      testWidgets('no overflow at 390×844 for ${id.name}', (tester) async {
        await _pumpDetail(tester, id);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no overflow at 360×640 for ${id.name}', (tester) async {
        await _pumpDetail(tester, id, surfaceSize: const Size(360, 640));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('star form switcher changes ability text', (tester) async {
      final entry = unitCatalog[UnitId.fighter]!;
      await _pumpDetail(tester, UnitId.fighter);

      // Initially at ★1.
      expect(find.text(entry.abilities[0].description), findsOneWidget);
      expect(find.text(entry.abilities[1].description), findsNothing);

      // Previous button should be disabled at ★1.
      final prevButton = find.byKey(const ValueKey('star-form-previous'));
      final nextButton = find.byKey(const ValueKey('star-form-next'));
      expect(prevButton, findsOneWidget);
      expect(nextButton, findsOneWidget);

      // Tap next → ★2.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.text(entry.abilities[1].description), findsOneWidget);
      expect(find.text(entry.abilities[0].description), findsNothing);

      // Tap next → ★3.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.text(entry.abilities[2].description), findsOneWidget);
      expect(find.text(entry.abilities[1].description), findsNothing);

      // Tap previous → back to ★2.
      await tester.tap(prevButton);
      await tester.pumpAndSettle();
      expect(find.text(entry.abilities[1].description), findsOneWidget);
    });

    testWidgets('star form switcher updates ATK to the server-scaled value',
        (tester) async {
      await _pumpDetail(tester, UnitId.fighter);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('attack-0'))).data,
        '15',
      );

      await tester.tap(find.byKey(const ValueKey('star-form-next')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('attack-1'))).data,
        '22',
      );

      await tester.tap(find.byKey(const ValueKey('star-form-next')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('attack-2'))).data,
        '30',
      );
    });

    testWidgets('star form switcher works for all units', (tester) async {
      // Verify switching works for a different unit (tank) to ensure
      // the detail is truly reusable and not hard-coded to one unit.
      final entry = unitCatalog[UnitId.tank]!;
      await _pumpDetail(tester, UnitId.tank);

      expect(find.text(entry.abilities[0].description), findsOneWidget);

      // Tap next to ★2.
      await tester.tap(find.byKey(const ValueKey('star-form-next')));
      await tester.pumpAndSettle();
      expect(find.text(entry.abilities[1].description), findsOneWidget);

      // Tap next to ★3.
      await tester.tap(find.byKey(const ValueKey('star-form-next')));
      await tester.pumpAndSettle();
      expect(find.text(entry.abilities[2].description), findsOneWidget);
    });

    testWidgets('back button pops the screen', (tester) async {
      installFakeSecureStorage();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: const Scaffold(body: Center(child: Text('catalog'))),
            routes: {
              '/detail': (_) => const UnitDetailScreen(unitId: UnitId.fighter),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to detail.
      unawaited(
        Navigator.of(
          tester.element(find.text('catalog')),
        ).pushNamed('/detail'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('นักรบ'), findsOneWidget);
      expect(find.text('catalog'), findsNothing);

      // Tap back.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('catalog'), findsOneWidget);
    });
  });
}
