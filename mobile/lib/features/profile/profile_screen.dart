import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/widgets.dart';
import 'settings_provider.dart';
import 'settings_tile.dart';

/// `/profile` — account info + settings + logout. Design spec §4.8, P1-FE-02.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const path = '/profile';
  static const _appVersion = '0.1.0+1'; // keep in sync with pubspec

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);

    return AppScaffold(
      title: 'โปรไฟล์',
      body: me.when(
        loading: () => const SingleChildScrollView(child: _ProfileSkeleton()),
        error: (_, __) => ErrorView(
          message: 'โหลดข้อมูลบัญชีไม่ได้ ลองอีกครั้ง',
          onRetry: () => ref.invalidate(_meProvider),
        ),
        data: (u) => SingleChildScrollView(child: _Content(user: u)),
      ),
    );
  }
}

/// `GET /user/me` → `{ id, email, username, rating }`.
final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(apiClientProvider).getMe();
});

class _Content extends ConsumerWidget {
  const _Content({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final game = t.extension<GameTheme>()!;
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final username = user['username'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final rating = user['rating'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  _initials(username),
                  style: t.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username, style: t.textTheme.titleLarge),
                    Text(
                      email,
                      style: t.textTheme.bodyMedium
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(Icons.military_tech, size: 16, color: game.gold),
                        const SizedBox(width: AppSpacing.xs),
                        Text('เรตติ้ง ${rating ?? '—'}',
                            style: t.textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          variant: AppButtonVariant.secondary,
          fullWidth: false,
          onPressed: () => _editUsername(context, ref, username),
          child: const Text('แก้ไขชื่อผู้ใช้'),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('ตั้งค่า', style: t.textTheme.titleLarge),
        const Divider(),
        SettingsTile(
          leading: Icons.brightness_6_outlined,
          title: 'ธีม',
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('ระบบ')),
              ButtonSegment(value: ThemeMode.light, label: Text('สว่าง')),
              ButtonSegment(value: ThemeMode.dark, label: Text('มืด')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settingsNotifier.setThemeMode(s.first),
          ),
        ),
        SettingsTile(
          leading: Icons.wifi_tethering,
          title: 'เชื่อมต่อใหม่อัตโนมัติ',
          subtitle: 'ต่อ WebSocket ใหม่เองเมื่อสัญญาณหลุด',
          trailing: Switch(
            value: settings.wsAutoReconnect,
            onChanged: settingsNotifier.setWsAutoReconnect,
          ),
        ),
        const Divider(),
        SettingsTile(
          leading: Icons.info_outline,
          title: 'เวอร์ชัน',
          trailing: Text(
            ProfileScreen._appVersion,
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          variant: AppButtonVariant.danger,
          onPressed: () => _logout(context, ref),
          child: const Text('ออกจากระบบ'),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await AppModal.confirm(
      context,
      title: 'ออกจากระบบ?',
      message: 'ต้องเข้าสู่ระบบใหม่เพื่อเล่นอีกครั้ง',
      confirmLabel: 'ออกจากระบบ',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(authRepositoryProvider).logout();
    AuthGate.instance.signalSignedOut();
    if (context.mounted) context.go('/login');
  }

  Future<void> _editUsername(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final saved = await AppModal.sheet<bool>(
      context,
      builder: (_) => _EditUsernameSheet(current: current),
    );
    if (saved == true) ref.invalidate(_meProvider);
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'[\s_]+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]);
    return letters.join().toUpperCase();
  }
}

class _EditUsernameSheet extends ConsumerStatefulWidget {
  const _EditUsernameSheet({required this.current});

  final String current;

  @override
  ConsumerState<_EditUsernameSheet> createState() => _EditUsernameSheetState();
}

class _EditUsernameSheetState extends ConsumerState<_EditUsernameSheet> {
  late final _ctrl = TextEditingController(text: widget.current);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _validate(String v) {
    final s = v.trim();
    if (s.isEmpty) return 'กรอกชื่อผู้ใช้';
    if (s.length < 3 || s.length > 20) return 'ยาว 3–20 ตัวอักษร';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(s)) {
      return 'ใช้ตัวอักษร ตัวเลข และ _ เท่านั้น';
    }
    return null;
  }

  Future<void> _save() async {
    final next = _ctrl.text.trim();
    final v = _validate(next);
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).updateMe(username: next);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.statusCode == 409
            ? 'ชื่อนี้ถูกใช้แล้ว'
            : 'บันทึกไม่สำเร็จ ลองอีกครั้ง';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('แก้ไขชื่อผู้ใช้', style: t.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          label: 'ชื่อผู้ใช้',
          controller: _ctrl,
          errorText: _error,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.username],
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          loading: _saving,
          onPressed: _saving ? null : _save,
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 96, radius: AppRadius.md),
        SizedBox(height: AppSpacing.xl),
        SkeletonBox(height: 48),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 48),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 48),
      ],
    );
  }
}
