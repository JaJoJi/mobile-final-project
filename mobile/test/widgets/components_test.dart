import 'package:auto_chess_mobile/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness.dart';

void main() {
  group('AppButton', () {
    testWidgets('renders each variant', (tester) async {
      for (final v in AppButtonVariant.values) {
        await pumpThemed(
          tester,
          AppButton(variant: v, onPressed: () {}, child: Text(v.name)),
        );
        expect(find.text(v.name), findsOneWidget);
      }
    });

    testWidgets('loading shows spinner and blocks taps', (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        AppButton(
          loading: true,
          onPressed: () => taps++,
          child: const Text('บันทึก'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      expect(taps, 0);
    });

    testWidgets('disabled shows the reason', (tester) async {
      await pumpThemed(
        tester,
        const AppButton(
          onPressed: null,
          disabledReason: 'ทองไม่พอ',
          child: Text('ซื้อ'),
        ),
      );
      expect(find.text('ทองไม่พอ'), findsOneWidget);
    });
  });

  testWidgets('AppTextField toggles password visibility', (tester) async {
    await pumpThemed(
      tester,
      const AppTextField(label: 'รหัสผ่าน', obscureText: true),
    );
    expect(find.text('รหัสผ่าน'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('AppCard interactive fires onTap', (tester) async {
    var tapped = false;
    await pumpThemed(
      tester,
      AppCard(
        variant: AppCardVariant.interactive,
        onTap: () => tapped = true,
        child: const Text('การ์ด'),
      ),
    );
    await tester.tap(find.text('การ์ด'));
    expect(tapped, isTrue);
  });

  group('HealthBar', () {
    testWidgets('shows numerals and a semantics label', (tester) async {
      await pumpThemed(
        tester,
        const SizedBox(width: 200, child: HealthBar(current: 60, max: 150)),
      );
      expect(find.text('60 / 150'), findsOneWidget);
      expect(
        find.bySemanticsLabel('พลังชีวิต 60 จาก 150'),
        findsOneWidget,
      );
    });

    testWidgets('low HP adds a warning icon (not colour alone)',
        (tester) async {
      await pumpThemed(
        tester,
        const SizedBox(width: 200, child: HealthBar(current: 10, max: 150)),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('UnitAvatar', () {
    testWidgets('shop variant shows name, price and star', (tester) async {
      await pumpThemed(
        tester,
        const UnitAvatar(
          unitId: 'ranger',
          star: 2,
          variant: UnitAvatarVariant.shop,
          size: UnitAvatarSize.lg,
          price: 2,
        ),
      );
      expect(find.text('Ranger'), findsOneWidget);
      expect(find.text('2g'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(2));
    });

    testWidgets('unknown unitId throws', (tester) async {
      expect(() => unitKindFromId('wizard'), throwsArgumentError);
    });

    testWidgets('renders the unit illustration', (tester) async {
      await pumpThemed(
        tester,
        const UnitAvatar(unitId: 'tank', star: 1),
      );
      final img = tester.widget<Image>(find.byType(Image));
      expect(img.image, isA<AssetImage>());
      expect(
        (img.image as AssetImage).assetName,
        'assets/images/units/tank.png',
      );
    });

    testWidgets('art path maps every unit id', (tester) async {
      for (final id in ['fighter', 'healer', 'ranger', 'tank']) {
        expect(
          unitKindFromId(id).artPath,
          'assets/images/units/$id.png',
        );
      }
    });

    testWidgets('sm size keeps a type glyph (no name label)', (tester) async {
      await pumpThemed(
        tester,
        const UnitAvatar(
          unitId: 'ranger',
          star: 0,
          size: UnitAvatarSize.sm,
          variant: UnitAvatarVariant.bench,
        ),
      );
      expect(find.text('Ranger'), findsNothing);
      expect(find.byIcon(Icons.change_history), findsOneWidget);
    });
  });

  testWidgets('PhaseTimerRing renders the remaining seconds', (tester) async {
    final base = DateTime(2026, 1, 1, 12);
    await pumpThemed(
      tester,
      PhaseTimerRing(
        durationSeconds: 40,
        clock: () => base,
        onExpire: () {},
      ),
    );
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('PhaseTimerRing calls onExpire and shows the waiting label',
      (tester) async {
    var expired = false;
    final base = DateTime(2026, 1, 1, 12);
    await pumpThemed(
      tester,
      PhaseTimerRing(
        deadline: base.subtract(const Duration(seconds: 1)),
        clock: () => base,
        onExpire: () => expired = true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(expired, isTrue);
    expect(find.text('รอเซิร์ฟเวอร์…'), findsOneWidget);
  });

  testWidgets('AppTabBar switches index', (tester) async {
    var index = 0;
    await pumpThemed(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppTabBar(
          currentIndex: index,
          onChanged: (i) => setState(() => index = i),
          tabs: const [
            AppTab(label: 'ทั้งหมด', icon: Icons.list),
            AppTab(label: 'ชนะ', icon: Icons.emoji_events_outlined),
          ],
        ),
      ),
    );
    await tester.tap(find.text('ชนะ'));
    await tester.pump();
    expect(index, 1);
  });

  testWidgets('state views render their contract', (tester) async {
    await pumpThemed(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 160,
            child: EmptyView(
              message: 'ยังไม่มีประวัติแมตช์',
              actionLabel: 'ค้นหาคู่แข่ง',
              onAction: () {},
            ),
          ),
          SizedBox(
            height: 160,
            child: ErrorView(message: 'เชื่อมต่อไม่ได้', onRetry: () {}),
          ),
        ],
      ),
    );
    expect(find.text('ยังไม่มีประวัติแมตช์'), findsOneWidget);
    expect(find.text('ค้นหาคู่แข่ง'), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('ConnectionBanner hides when connected', (tester) async {
    await pumpThemed(
      tester,
      const ConnectionBanner(status: ConnectionStatus.connected),
    );
    expect(find.byType(SizedBox), findsWidgets); // shrink placeholder only
    expect(find.textContaining('เชื่อมต่อ'), findsNothing);
  });

  testWidgets('AppToast shows a snackbar', (tester) async {
    await pumpThemed(
      tester,
      Builder(
        builder: (context) => AppButton(
          onPressed: () => AppToast.show(
            context,
            'บันทึกแล้ว',
            variant: AppToastVariant.success,
          ),
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
  });
}
