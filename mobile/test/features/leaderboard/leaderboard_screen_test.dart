import 'dart:async';

import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/leaderboard/leaderboard_screen.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_fixture_provider.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({
    Future<LeaderboardViewData> Function(Ref ref)? source,
    double textScale = 1,
  }) =>
      ProviderScope(
        overrides: [
          if (source != null) leaderboardSourceProvider.overrideWith(source),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const LeaderboardScreen(),
        ),
      );

  testWidgets('shows the V2 champion, first five rows, and current rank', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('ตารางอันดับ'), findsOneWidget);
    expect(find.text('ผู้บัญชาการแห่งสนาม · เรียงตามเรตติ้ง'), findsOneWidget);
    expect(find.text('MoonKnight'), findsWidgets);
    expect(find.text('อันดับ'), findsOneWidget);
    expect(find.text('ผู้เล่น'), findsOneWidget);
    expect(find.text('เรตติ้ง'), findsWidgets);
    expect(find.text('ForestMage'), findsOneWidget);
    expect(find.text('SilverPawn'), findsNothing);
    expect(find.text('อันดับของคุณ'), findsOneWidget);
    expect(find.text('#28'), findsOneWidget);
    expect(find.text('JaJoJi'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);
  });

  testWidgets('reveals the final fixture rows only after loading more', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('โหลดเพิ่มเติม'));
    await tester.tap(find.text('โหลดเพิ่มเติม'));
    await tester.pumpAndSettle();

    expect(find.text('SilverPawn'), findsOneWidget);
    expect(find.text('NightOwl'), findsOneWidget);
    expect(find.text('แสดงข้อมูลตัวอย่างครบแล้ว'), findsOneWidget);
  });

  testWidgets('shows a loading state while the source is pending',
      (tester) async {
    final pending = Completer<LeaderboardViewData>();
    await tester.pumpWidget(app(source: (_) => pending.future));
    await tester.pump();

    expect(find.text('กำลังโหลดข้อมูล…'), findsOneWidget);
  });

  testWidgets('shows an empty leaderboard state', (tester) async {
    final empty = LeaderboardViewData(
      entries: const [],
      currentPlayer: const LeaderboardEntry(
        rank: 28,
        username: 'JaJoJi',
        rating: 1240,
      ),
    );
    await tester.pumpWidget(app(source: (_) async => empty));
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีข้อมูลอันดับ'), findsOneWidget);
    expect(find.text('อันดับของคุณ'), findsOneWidget);
    expect(find.text('#28'), findsOneWidget);
  });

  testWidgets('highlights the current player when present in loaded rows', (
    tester,
  ) async {
    final data = LeaderboardViewData(
      entries: const [
        LeaderboardEntry(rank: 1, username: 'Top', rating: 1800),
        LeaderboardEntry(rank: 2, username: 'Second', rating: 1700),
        LeaderboardEntry(rank: 3, username: 'JaJoJi', rating: 1600),
      ],
      currentPlayer: const LeaderboardEntry(
        rank: 3,
        username: 'JaJoJi',
        rating: 1600,
      ),
    );
    await tester.pumpWidget(app(source: (_) async => data));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('leaderboard-self-row')), findsOneWidget);
  });

  testWidgets('retries a failed leaderboard source without leaving the page', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      app(
        source: (_) async {
          if (attempts++ == 0) throw StateError('offline');
          return PlayerHubFixtures.leaderboard;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(find.text('ตารางอันดับ'), findsOneWidget);
    expect(find.text('MoonKnight'), findsWidgets);
    expect(find.text('โหลดข้อมูลไม่สำเร็จ'), findsNothing);
  });

  testWidgets('does not overflow at 360x640 with text scale 2', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('leaderboard-champion-compact')),
      findsOneWidget,
    );
  });
}
