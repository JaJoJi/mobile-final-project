import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/auth/auth_repository.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/core/ws/ws_client.dart';
import 'package:auto_chess_mobile/core/ws/ws_providers.dart';
import 'package:auto_chess_mobile/features/rooms/create_room_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/ws/fake_ws_transport.dart';

class _RoomApi extends ApiClient {
  bool created = false;
  bool missing = false;
  String? guestId;
  int startCalls = 0;

  Map<String, dynamic> get room => {
        'roomId': 'room-1',
        'code': 'ABC234',
        'ownerId': 'owner-1',
        'ownerUsername': 'Alice',
        'guestUsername': guestId == null ? null : 'Bob',
        'guestId': guestId,
        'status': guestId == null ? 'waiting' : 'full',
        'expiresAt': '2026-10-01T00:00:00Z',
        'matchId': null,
      };

  @override
  Future<Map<String, dynamic>> getMyRoom() async {
    if (missing) {
      throw DioException(
        requestOptions: RequestOptions(path: '/rooms/mine'),
        response: Response(
          requestOptions: RequestOptions(path: '/rooms/mine'),
          statusCode: 404,
        ),
      );
    }
    return room;
  }

  @override
  Future<Map<String, dynamic>> createRoom() async {
    created = true;
    missing = false;
    return room;
  }

  @override
  Future<Map<String, dynamic>> getMe() async => {'username': 'Alice'};

  @override
  Future<Map<String, dynamic>> startRoom() async {
    startCalls++;
    return {};
  }
}

class _Auth extends AuthRepository {
  _Auth(super.api, {this.userId = 'owner-1'});

  final String userId;

  @override
  Future<String?> getUserId() async => userId;
}

void main() {
  late _RoomApi api;
  late WsClient ws;
  late FakeWsTransport transport;

  setUp(() async {
    api = _RoomApi();
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

  Widget app({String userId = 'owner-1'}) => ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authRepositoryProvider.overrideWithValue(
            _Auth(api, userId: userId),
          ),
          wsClientProvider.overrideWithValue(ws),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const CreateRoomScreen(),
        ),
      );

  testWidgets('creates a room when none exists and shows the returned code',
      (tester) async {
    api.missing = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(api.created, isTrue);
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('เจ้าของห้อง'), findsOneWidget);
    expect(find.text('คุณ · เจ้าของห้อง'), findsNothing);
    expect(find.text('กำลังรอผู้ท้าชิง'), findsOneWidget);
    expect(find.text('ออโต้เชส / ประลองกับเพื่อน'), findsNothing);
  });

  testWidgets('animates the hourglass while waiting for a challenger', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final rotation = tester.widget<RotationTransition>(
      find.byKey(const ValueKey('waiting-hourglass-rotation')),
    );
    expect(rotation.turns.value, 0);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    expect(rotation.turns.value, greaterThan(0));
  });

  testWidgets('shows the guest from the room response', (tester) async {
    api.guestId = 'guest-2';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('เริ่มเกม'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-room-match-button')));
    await tester.pump();
    expect(api.startCalls, 1);
  });

  testWidgets('start stays disabled until a guest joins', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-room-match-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('รอผู้ท้าชิง'), findsWidgets);
  });

  testWidgets('guest enters the same lobby on the right and waits for host',
      (tester) async {
    api.guestId = 'guest-2';
    await tester.pumpWidget(app(userId: 'guest-2'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Alice')).dx,
      lessThan(tester.getCenter(find.text('Bob')).dx),
    );
    expect(find.text('รอเจ้าของห้องเริ่มเกม'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('start-room-match-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('keeps the arena readable at 360 pixels', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets('back action opens the themed leave confirmation',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    await tester.tap(find.byTooltip('ออกจากห้อง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ออกจากห้องนี้?'), findsOneWidget);
    expect(find.text('อยู่ในห้องต่อ'), findsOneWidget);
    expect(find.text('ออกจากห้อง'), findsOneWidget);
  });
}
