import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_fixture_provider.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_models.dart';
import 'package:auto_chess_mobile/features/rooms/create_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({RoomViewState? room, double textScale = 1}) => ProviderScope(
        overrides: [
          if (room != null) roomFixtureProvider.overrideWithValue(room),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const CreateRoomScreen(),
        ),
      );

  testWidgets('shows the V2 arena with host, VS, invite code and waiting state',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('ห้องส่วนตัว'), findsOneWidget);
    expect(find.text('K7M2Q9'), findsOneWidget);
    expect(find.text('คัดลอก'), findsOneWidget);
    expect(find.text('JaJoJi'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('รอคู่แข่ง'), findsOneWidget);
    expect(find.text('กำลังรอผู้ท้าชิง'), findsOneWidget);
    expect(find.text('ไม่มีห้องจริงหรือการเริ่มเกม'), findsOneWidget);
    expect(find.text('เชื่อมต่อแล้ว'), findsNothing);
  });

  testWidgets('renders joined and reconnecting fixture states', (tester) async {
    await tester.pumpWidget(app(room: PlayerHubFixtures.joined));
    await tester.pumpAndSettle();
    expect(find.text('ผู้เล่น 2 / 2'), findsOneWidget);
    expect(find.text('Astra'), findsOneWidget);
    expect(find.text('ผู้ท้าชิงเข้าร่วมแล้ว'), findsOneWidget);

    await tester.pumpWidget(app(room: PlayerHubFixtures.reconnecting));
    await tester.pumpAndSettle();
    expect(find.text('จำลองการเชื่อมต่อใหม่'), findsOneWidget);
  });

  testWidgets('does not overflow at 360x640 with text scale 2', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('VS'), findsOneWidget);
  });
}
