import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/lobby/player_hub_navigation.dart';
import 'package:auto_chess_mobile/features/units/unit_catalog_card.dart';
import 'package:auto_chess_mobile/features/units/unit_detail_screen.dart';
import 'package:auto_chess_mobile/features/units/units_screen.dart';
import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:auto_chess_mobile/shared/models/unit_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../_util.dart';

/// Stub page that shows which route was navigated to.
class _Stub extends StatelessWidget {
  const _Stub(this.tag);
  final String tag;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:$tag')));
}

/// Pump the [UnitsScreen] inside a GoRouter with stub detail and hub routes.
Future<GoRouter> _pumpUnits(
  WidgetTester tester, {
  Size surfaceSize = const Size(390, 844),
}) async {
  installFakeSecureStorage();

  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/units',
    routes: [
      GoRoute(path: '/units', builder: (_, __) => const UnitsScreen()),
      GoRoute(
        path: '/units/:unitId',
        builder: (_, state) =>
            _Stub('detail:${state.pathParameters['unitId']}'),
      ),
      GoRoute(path: '/lobby', builder: (_, __) => const _Stub('lobby')),
      GoRoute(path: '/history', builder: (_, __) => const _Stub('history')),
      GoRoute(path: '/profile', builder: (_, __) => const _Stub('profile')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: buildTheme(Brightness.dark),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('renders all 4 unit names from the catalog', (tester) async {
    await _pumpUnits(tester);

    for (final entry in unitCatalog.values) {
      expect(
        find.text(entry.name),
        findsOneWidget,
        reason: '${entry.id} name "${entry.name}" should be visible',
      );
    }
  });

  testWidgets('renders roles for each unit', (tester) async {
    await _pumpUnits(tester);

    for (final entry in unitCatalog.values) {
      expect(
        find.text(entry.role),
        findsOneWidget,
        reason: '${entry.id} role "${entry.role}" should be visible',
      );
    }
  });

  testWidgets('renders 4 UnitCatalogCard widgets', (tester) async {
    await _pumpUnits(tester);

    expect(find.byType(UnitCatalogCard), findsNWidgets(4));
  });

  testWidgets('shows the PlayerHubNavigation with units tab', (tester) async {
    await _pumpUnits(tester);

    expect(find.byType(PlayerHubNavigation), findsOneWidget);
    // The Thai label for the units tab.
    expect(find.text('ยูนิต'), findsOneWidget);
  });

  testWidgets('shows the catalog header', (tester) async {
    await _pumpUnits(tester);

    expect(find.text('คลังยูนิต'), findsOneWidget);
  });

  testWidgets('tapping a unit card navigates to the detail route',
      (tester) async {
    final router = await _pumpUnits(tester);

    // Tap the first card (fighter).
    await tester.tap(find.byType(UnitCatalogCard).first);
    await tester.pumpAndSettle();

    expect(
      find.text('stub:detail:fighter'),
      findsOneWidget,
      reason: 'should have pushed /units/fighter',
    );

    // Go back and tap the last card (tank).
    router.go('/units');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(UnitCatalogCard).last);
    await tester.pumpAndSettle();

    expect(
      find.text('stub:detail:tank'),
      findsOneWidget,
      reason: 'should have pushed /units/tank',
    );
  });

  testWidgets('no overflow at 390×844 portrait', (tester) async {
    await _pumpUnits(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 360×640 compact', (tester) async {
    await _pumpUnits(tester, surfaceSize: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 900×500 landscape', (tester) async {
    await _pumpUnits(tester, surfaceSize: const Size(900, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid unitId redirects to catalog', (tester) async {
    final router = GoRouter(
      initialLocation: '/units/invalid123',
      routes: [
        GoRoute(
          path: UnitsScreen.path,
          builder: (_, __) => const UnitsScreen(),
        ),
        GoRoute(
          path: UnitDetailScreen.path,
          redirect: (context, state) {
            final idString = state.pathParameters['unitId'];
            if (idString == null ||
                !UnitId.values.any((e) => e.toJson() == idString)) {
              return UnitsScreen.path;
            }
            return null;
          },
          builder: (_, state) => UnitDetailScreen(
            unitId: UnitId.fromJson(state.pathParameters['unitId']),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UnitsScreen), findsOneWidget);
    expect(find.byType(UnitDetailScreen), findsNothing);
  });
}
