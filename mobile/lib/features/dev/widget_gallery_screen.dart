import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';

/// A live catalogue of every `core/widgets/` component in each of its
/// states — the "storybook" the P0-FE-06 issue asks for. Not shipped in
/// any user flow; reachable via `/dev/gallery` for design review.
class WidgetGalleryScreen extends StatefulWidget {
  const WidgetGalleryScreen({super.key});

  @override
  State<WidgetGalleryScreen> createState() => _WidgetGalleryScreenState();
}

class _WidgetGalleryScreenState extends State<WidgetGalleryScreen> {
  Brightness _brightness = Brightness.light;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildTheme(_brightness),
      child: Builder(
        builder: (context) => AppScaffold(
          title: 'Widget Gallery',
          actions: [
            IconButton(
              tooltip: _brightness == Brightness.light
                  ? 'สลับเป็นธีมมืด'
                  : 'สลับเป็นธีมสว่าง',
              icon: Icon(_brightness == Brightness.light
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined),
              onPressed: () => setState(() {
                _brightness = _brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light;
              }),
            ),
          ],
          scrollable: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('AppButton', [
                for (final v in AppButtonVariant.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppButton(
                      variant: v,
                      onPressed: () {},
                      child: Text(v.name),
                    ),
                  ),
                const AppButton(
                  onPressed: null,
                  loading: true,
                  child: Text('กำลังบันทึก'),
                ),
                const AppButton(
                  onPressed: null,
                  disabledReason: 'ทองไม่พอ',
                  child: Text('ซื้อ'),
                ),
              ]),
              _section('AppTextField', const [
                AppTextField(
                  label: 'อีเมล',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: [AutofillHints.email],
                  prefixIcon: Icons.mail_outline,
                ),
                SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'รหัสผ่าน',
                  obscureText: true,
                  errorText: 'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร',
                  textInputAction: TextInputAction.done,
                  autofillHints: [AutofillHints.password],
                ),
              ]),
              _section('AppCard', [
                const AppCard(child: Text('flat')),
                const SizedBox(height: AppSpacing.sm),
                const AppCard(
                  variant: AppCardVariant.raised,
                  selected: true,
                  child: Text('raised + selected'),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  variant: AppCardVariant.interactive,
                  onTap: () {},
                  child: const Text('interactive'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppCard(disabled: true, child: Text('disabled')),
              ]),
              _section('HealthBar', const [
                HealthBar(current: 150, max: 150, size: HealthBarSize.lg),
                SizedBox(height: AppSpacing.md),
                HealthBar(current: 60, max: 150),
                SizedBox(height: AppSpacing.md),
                HealthBar(current: 18, max: 150),
              ]),
              _section('UnitAvatar', const [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    UnitAvatar(
                      unitId: 'ranger',
                      star: 1,
                      variant: UnitAvatarVariant.shop,
                      size: UnitAvatarSize.lg,
                      price: 2,
                    ),
                    UnitAvatar(
                      unitId: 'fighter',
                      star: 2,
                      variant: UnitAvatarVariant.board,
                      hp: 40,
                      maxHp: 100,
                    ),
                    UnitAvatar(
                      unitId: 'healer',
                      star: 0,
                      size: UnitAvatarSize.sm,
                      variant: UnitAvatarVariant.bench,
                    ),
                    UnitAvatar(
                      unitId: 'tank',
                      star: 1,
                      state: UnitAvatarState.fusable,
                    ),
                    UnitAvatar(
                      unitId: 'ranger',
                      star: 2,
                      variant: UnitAvatarVariant.shop,
                      state: UnitAvatarState.unaffordable,
                      price: 2,
                    ),
                    UnitAvatar(
                      unitId: 'fighter',
                      star: 0,
                      state: UnitAvatarState.dead,
                    ),
                  ],
                ),
              ]),
              _section('PhaseTimerRing', [
                Wrap(
                  spacing: AppSpacing.xl,
                  children: [
                    PhaseTimerRing(durationSeconds: 40, onExpire: () {}),
                    PhaseTimerRing(durationSeconds: 8, onExpire: () {}),
                    PhaseTimerRing(durationSeconds: 4, onExpire: () {}),
                  ],
                ),
              ]),
              _section('AppTabBar', [
                AppTabBar(
                  currentIndex: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                  tabs: const [
                    AppTab(label: 'ทั้งหมด', icon: Icons.list),
                    AppTab(label: 'ชนะ', icon: Icons.emoji_events_outlined),
                    AppTab(label: 'แพ้', icon: Icons.close),
                  ],
                ),
              ]),
              _section('AppToast / AppModal', [
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton(
                      onPressed: () => AppToast.show(context, 'บันทึกแล้ว',
                          variant: AppToastVariant.success),
                      child: const Text('toast success'),
                    ),
                    OutlinedButton(
                      onPressed: () => AppToast.show(
                          context, 'การเชื่อมต่อหลุด',
                          variant: AppToastVariant.danger),
                      child: const Text('toast danger'),
                    ),
                    OutlinedButton(
                      onPressed: () => AppModal.confirm(
                        context,
                        title: 'ขาย unit นี้?',
                        message: 'จะได้ทองคืนเต็มจำนวน',
                        confirmLabel: 'ขาย',
                        destructive: true,
                      ),
                      child: const Text('confirm (destructive)'),
                    ),
                  ],
                ),
              ]),
              _section('State views', [
                const SizedBox(height: 120, child: SkeletonList(rows: 2)),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 200,
                  child: EmptyView(
                    message: 'ยังไม่มีประวัติแมตช์',
                    actionLabel: 'ค้นหาคู่แข่ง',
                    onAction: () {},
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: ErrorView(
                    message:
                        'เชื่อมต่อไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง',
                    onRetry: () {},
                  ),
                ),
                const ConnectionBanner(
                  status: ConnectionStatus.reconnecting,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}
