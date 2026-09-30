import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/core/widgets/health_bar.dart';
import 'package:auto_chess_mobile/core/widgets/unit_detail_sheet.dart';
import 'package:auto_chess_mobile/features/lobby/player_hub_navigation.dart';
import 'package:auto_chess_mobile/features/units/units_screen.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:auto_chess_mobile/shared/models/unit_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Units tab navigates to the four-unit catalog', (tester) async {
    final router = GoRouter(
      initialLocation: '/lobby',
      routes: [
        GoRoute(
          path: '/lobby',
          builder: (_, __) => const Scaffold(
            body: PlayerHubNavigation(selected: PlayerHubTab.home),
          ),
        ),
        GoRoute(path: '/units', builder: (_, __) => const UnitsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        routerConfig: router,
      ),
    );
    await tester.tap(find.text('ยูนิต'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, UnitsScreen.path);
    expect(find.byType(UnitsScreen), findsOneWidget);
    for (final entry in UnitCatalogEntry.entries) {
      expect(
        find.byKey(ValueKey('unit-card-${entry.id.name}')),
        findsOneWidget,
      );
    }
    expect(find.text('ระบบยูนิตจะเปิดให้ใช้งานเร็ว ๆ นี้'), findsNothing);
  });

  testWidgets('each card opens shared details and switches through 1–3 stars',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const UnitsScreen(),
      ),
    );

    for (final entry in UnitCatalogEntry.entries) {
      final card = find.byKey(ValueKey('unit-card-${entry.id.name}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      final sheet = find.byType(UnitDetailSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text(entry.name)),
        findsOneWidget,
      );
      expect(find.byType(HealthBar), findsNothing);

      for (var tier = 0; tier <= 2; tier++) {
        await tester.tap(find.byKey(ValueKey('unit-tier-$tier')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: sheet,
            matching: find.text('${entry.atkForTier(tier)}'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sheet,
            matching: find.text(entry.abilityForTier(tier)),
          ),
          findsOneWidget,
        );
      }
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('match detail shows current HP without catalog tier controls',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: UnitDetailSheet(
            unitId: UnitId.fighter,
            star: 1,
            hp: 37,
            maxHp: 100,
          ),
        ),
      ),
    );
    expect(find.byType(HealthBar), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-tier-0')), findsNothing);
    expect(find.text('2 ดาว · ไฟต์เตอร์'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
  });

  testWidgets('catalog and detail fit narrow scaled text and tablet layouts',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: UnitsScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: UnitDetailSheet(unitId: UnitId.fighter, star: 2),
          ),
        ),
      ),
    );
    expect(find.text('นักรบ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const UnitsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in UnitCatalogEntry.entries) {
      expect(
        find.byKey(ValueKey('unit-card-${entry.id.name}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
