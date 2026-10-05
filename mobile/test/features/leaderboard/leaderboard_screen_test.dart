import 'dart:async';

import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/leaderboard/leaderboard_screen.dart';
import 'package:auto_chess_mobile/features/lobby/profile_card.dart';
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
          currentUserProvider.overrideWith(
            (_) async => {
              'id': 'self',
              'username': 'JaJoJi',
              'rating': 1240,
            },
          ),
          leaderboardSourceProvider.overrideWith(
            source ?? (_) async => PlayerHubFixtures.leaderboard,
          ),
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

  testWidgets('shows current rank before the first five leaderboard rows', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('ตารางอันดับ'), findsOneWidget);
    expect(find.text('ผู้บัญชาการแห่งสนาม · เรียงตามเรตติ้ง'), findsNothing);
    expect(find.text('MoonKnight'), findsOneWidget);
    expect(find.text('อันดับผู้เล่น'), findsOneWidget);
    expect(find.text('ForestMage'), findsOneWidget);
    expect(find.text('SilverPawn'), findsNothing);
    expect(find.text('อันดับของคุณ'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('JaJoJi'), findsWidgets);
    expect(find.text('1,240'), findsWidgets);
  });

  testWidgets('reveals the final fixture rows only after loading more', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('โหลดเพิ่มเติม'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โหลดเพิ่มเติม'));
    await tester.pumpAndSettle();

    expect(find.text('SilverPawn'), findsOneWidget);
    expect(find.text('NightOwl'), findsOneWidget);
    expect(find.text('โหลดเพิ่มเติม'), findsNothing);
    expect(find.text('ย่อรายการ'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ย่อรายการ'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ย่อรายการ'));
    await tester.pumpAndSettle();

    expect(find.text('SilverPawn'), findsNothing);
    expect(find.text('NightOwl'), findsNothing);
    expect(find.text('โหลดเพิ่มเติม'), findsOneWidget);
  });

  for (final (rank, icon, color) in [
    (1, Icons.emoji_events_rounded, const Color(0xFFFFD35A)),
    (2, Icons.workspace_premium_rounded, const Color(0xFFC9D7E5)),
    (3, Icons.military_tech_rounded, const Color(0xFFD99A62)),
    (28, Icons.shield_outlined, const Color(0xFF8FA8BE)),
  ]) {
    testWidgets('current rank $rank uses the leaderboard medal style',
        (tester) async {
      final data = LeaderboardViewData(
        entries: PlayerHubFixtures.leaderboard.entries,
        currentPlayer:
            LeaderboardEntry(rank: rank, username: 'JaJoJi', rating: 1240),
      );
      await tester.pumpWidget(app(source: (_) async => data));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('leaderboard-current-rank-card'));
      final medal = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Icon && widget.icon == icon && widget.size == 27,
        ),
      );
      expect(medal, findsOneWidget);
      expect(tester.widget<Icon>(medal).color, color.withValues(alpha: .22));
      final label = tester.widget<Text>(
        find.descendant(of: card, matching: find.text('$rank')),
      );
      expect(label.style?.color, color);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows a loading state while the source is pending',
      (tester) async {
    final pending = Completer<LeaderboardViewData>();
    await tester.pumpWidget(app(source: (_) => pending.future));
    await tester.pump();

    expect(find.bySemanticsLabel('กำลังโหลดข้อมูล…'), findsOneWidget);
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
    expect(find.text('28'), findsOneWidget);
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
      find.byKey(const ValueKey('leaderboard-current-rank-card')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the home destination selected in bottom navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('หน้าหลัก'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('หน้าหลัก')),
      matchesSemantics(
        label: 'หน้าหลัก',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
  });
}
