import 'dart:convert';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/player_hub/player_crest.dart';
import 'package:auto_chess_mobile/features/profile/profile_screen.dart';
import 'package:auto_chess_mobile/features/profile/settings_provider.dart';
import 'package:auto_chess_mobile/features/profile/settings_tile.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void _installFakeSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> app({
    required _FakeAdapter adapter,
    double textScale = 1.0,
    GoRouter? router,
  }) async {
    SharedPreferences.setMockInitialValues({});
    _installFakeSecureStorage();
    final prefs = await SharedPreferences.getInstance();

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      ],
      child: router == null
          ? MaterialApp(
              theme: buildTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: const ProfileScreen(),
            )
          : MaterialApp.router(
              theme: buildTheme(Brightness.light),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
            ),
    );
  }

  final okMe = _FakeAdapter((o) {
    if (o.path == '/user/me') {
      return _json(
        {
          'id': 'u1',
          'username': 'alice',
          'email': 'alice@example.com',
          'rating': 1200,
        },
        200,
      );
    }
    return _json({}, 404);
  });

  testWidgets('shows the exact V2 identity rating presentation', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('เรตติ้งปัจจุบัน'), findsOneWidget);
    expect(find.text('แมตช์ที่จบแล้ว'), findsOneWidget);
  });

  testWidgets('uses the V2 player hub chrome around the profile data',
      (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    expect(find.text('โปรไฟล์ผู้บัญชาการ'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-crest')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-hub-navigation')), findsOneWidget);
    expect(find.text('บันทึกการประลอง'), findsOneWidget);
  });

  testWidgets('shows the V2 rank, history, and private-account hierarchy',
      (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    expect(find.text('ดูตารางอันดับ'), findsOneWidget);
    expect(find.text('ทุกแมตช์คือประสบการณ์'), findsOneWidget);
    expect(find.text('ดูประวัติการแข่งขัน'), findsOneWidget);
    expect(find.text('ข้อมูลบัญชีเป็นส่วนตัว'), findsOneWidget);
  });

  testWidgets('opens the Player Hub rank and history destinations',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ProfileScreen()),
        GoRoute(
          path: '/leaderboard',
          builder: (_, __) => const Scaffold(body: Text('leaderboard route')),
        ),
        GoRoute(
          path: '/history',
          builder: (_, __) => const Scaffold(body: Text('history route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(await app(adapter: okMe, router: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ดูตารางอันดับ'));
    await tester.tap(find.text('ดูตารางอันดับ'));
    await tester.pumpAndSettle();
    expect(find.text('leaderboard route'), findsOneWidget);

    router.go('/');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ดูประวัติการแข่งขัน'));
    await tester.tap(find.text('ดูประวัติการแข่งขัน'));
    await tester.pumpAndSettle();
    expect(find.text('history route'), findsOneWidget);
  });

  testWidgets('shows the player statistics returned by the statistics API',
      (tester) async {
    final meAndStats = _FakeAdapter((o) {
      if (o.path == '/user/me') {
        return _json(
          {
            'id': 'u1',
            'username': 'alice',
            'email': 'alice@example.com',
            'rating': 1200,
          },
          200,
        );
      }
      if (o.path == '/user/me/stats') {
        return _json(
          {
            'matches': 42,
            'wins': 26,
            'losses': 16,
            'winRate': 61.9,
            'currentRank': 28,
          },
          200,
        );
      }
      return _json({}, 404);
    });

    await tester.pumpWidget(await app(adapter: meAndStats));
    await tester.pumpAndSettle();

    expect(find.text('บันทึกการประลอง'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('26'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('61.9%'), findsOneWidget);
    expect(find.text('อันดับ #28'), findsOneWidget);
    expect(find.text('บนตารางอันดับ'), findsOneWidget);
  });

  testWidgets('guides a new player who has no completed matches',
      (tester) async {
    final newPlayer = _FakeAdapter((o) {
      if (o.path == '/user/me') {
        return _json(
          {
            'id': 'u2',
            'username': 'new_player',
            'email': 'new@example.com',
            'rating': 1000,
          },
          200,
        );
      }
      if (o.path == '/user/me/stats') {
        return _json(
          {
            'matches': 0,
            'wins': 0,
            'losses': 0,
            'winRate': null,
            'currentRank': null,
          },
          200,
        );
      }
      return _json({}, 404);
    });

    await tester.pumpWidget(await app(adapter: newPlayer));
    await tester.pumpAndSettle();

    expect(find.text('ลงสนามครั้งแรกเพื่อเริ่มบันทึกสถิติ'), findsOneWidget);
    expect(find.text('ยังไม่มีอันดับ'), findsOneWidget);
  });

  testWidgets('keeps account information visible when statistics fail',
      (tester) async {
    final statsFail = _FakeAdapter((o) {
      if (o.path == '/user/me') {
        return _json(
          {
            'id': 'u1',
            'username': 'alice',
            'email': 'alice@example.com',
            'rating': 1200,
          },
          200,
        );
      }
      if (o.path == '/user/me/stats') return _json({'message': 'boom'}, 500);
      return _json({}, 404);
    });

    await tester.pumpWidget(await app(adapter: statsFail));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('โหลดสถิติการแข่งขันไม่ได้'), findsOneWidget);
    expect(find.text('แก้ไขชื่อผู้ใช้'), findsOneWidget);
  });

  testWidgets('theme segmented button drives settingsProvider', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    );
    expect(container.read(settingsProvider).themeMode, ThemeMode.system);

    await tester.ensureVisible(find.text('มืด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('มืด'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
  });

  testWidgets('sound switch drives settingsProvider', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileScreen)),
    );
    final soundTile = find.ancestor(
      of: find.text('เสียงเอฟเฟกต์'),
      matching: find.byType(SettingsTile),
    );
    await tester.ensureVisible(soundTile);
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: soundTile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).soundEnabled, isFalse);
  });

  testWidgets('logout asks for confirmation', (tester) async {
    AuthGate.instance.signalSignedIn();
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();

    expect(find.text('ออกจากระบบ?'), findsOneWidget); // confirm dialog title
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(AuthGate.instance.isSignedIn, isTrue); // cancelled → still signed in
  });

  testWidgets('error state offers a retry', (tester) async {
    final failMe = _FakeAdapter((_) => _json({'message': 'boom'}, 500));
    await tester.pumpWidget(await app(adapter: failMe));
    await tester.pumpAndSettle();

    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('meets tap-target / contrast / label guidelines', (tester) async {
    await tester.pumpWidget(await app(adapter: okMe));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('no overflow at 360x640 and textScale 2.0', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await app(adapter: okMe, textScale: 2.0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps long identity details usable on a narrow V2 profile',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final longIdentity = _FakeAdapter((o) {
      if (o.path == '/user/me') {
        return _json(
          {
            'id': 'u3',
            'username': 'commander_with_an_exceptionally_long_name',
            'email': 'commander.with.a.very.long.address@example.com',
            'rating': 1240,
          },
          200,
        );
      }
      if (o.path == '/user/me/stats') {
        return _json(
          {
            'matches': 42,
            'wins': 26,
            'losses': 16,
            'winRate': 61.9,
            'currentRank': 28,
          },
          200,
        );
      }
      return _json({}, 404);
    });

    await tester.pumpWidget(await app(adapter: longIdentity, textScale: 2.0));
    await tester.pumpAndSettle();

    expect(
      find.text('commander_with_an_exceptionally_long_name'),
      findsOneWidget,
    );
    expect(
      find.text('commander.with.a.very.long.address@example.com'),
      findsOneWidget,
    );
    expect(find.text('1,240'), findsOneWidget);
    expect(find.text('เรตติ้งปัจจุบัน'), findsOneWidget);
    expect(find.text('แมตช์ที่จบแล้ว'), findsOneWidget);
    expect(find.text('อันดับ #28'), findsOneWidget);
    expect(find.text('บนตารางอันดับ'), findsOneWidget);
    expect(find.text('ดูตารางอันดับ'), findsOneWidget);
    expect(tester.widget<PlayerCrest>(find.byType(PlayerCrest)).compact, isTrue);
    expect(tester.takeException(), isNull);
  });
}
