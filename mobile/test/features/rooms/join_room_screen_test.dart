import 'dart:async';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/rooms/join_room_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../core/ws/fake_ws_transport.dart';

class _JoinApi extends ApiClient {
  String? submittedCode;
  String? failureCode;
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> joinRoom(String code) async {
    submittedCode = code;
    if (pending != null) return pending!.future;
    if (failureCode != null) {
      final request = RequestOptions(path: '/rooms/join');
      throw DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 404,
          data: {'code': failureCode},
        ),
      );
    }
    return {'matchId': 'match-1', 'status': 'matched'};
  }
}

void main() {
  late _JoinApi api;
  late WsClient ws;
  late FakeWsTransport transport;

  setUp(() async {
    api = _JoinApi();
    transport = FakeWsTransport();
    ws = WsClient(
      url: 'ws://localhost',
      getAccessToken: () async => 'token',
      transport: transport,
    );
    final connected = ws.connect();
    transport.serverConnect();
    await connected;
  });

  tearDown(() => ws.dispose());

  Future<void> pumpJoin(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/rooms/join',
      routes: [
        GoRoute(
          path: '/rooms/join',
          builder: (_, __) => const JoinRoomScreen(),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (_, state) =>
              Scaffold(body: Text('match:${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/rooms/create',
          builder: (_, __) => const Scaffold(body: Text('create')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          wsClientProvider.overrideWithValue(ws),
        ],
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('พบเพื่อนในสนามส่วนตัว'), findsNothing);
  }

  testWidgets('normalizes a pasted code and enters the returned match',
      (tester) async {
    await pumpJoin(tester);
    await tester.enterText(find.byType(TextField), ' abc234 ');
    await tester.pump();
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.pumpAndSettle();

    expect(api.submittedCode, 'ABC234');
    expect(find.text('match:match-1'), findsOneWidget);
  });

  testWidgets('shows a distinct error when the room is missing',
      (tester) async {
    api.failureCode = 'room.not_found';
    await pumpJoin(tester);
    await tester.enterText(find.byType(TextField), 'ABC234');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่พบห้องนี้ หรือห้องหมดอายุแล้ว'), findsOneWidget);
  });

  testWidgets('does not submit twice while join is pending', (tester) async {
    api.pending = Completer<Map<String, dynamic>>();
    await pumpJoin(tester);
    await tester.enterText(find.byType(TextField), 'ABC234');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าร่วมห้อง'));
    await tester.pump();

    expect(
      find.widgetWithText(FilledButton, 'กำลังเข้าร่วมห้อง…'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    api.pending!.complete({'matchId': 'match-1', 'status': 'matched'});
    await tester.pumpAndSettle();
  });
}
