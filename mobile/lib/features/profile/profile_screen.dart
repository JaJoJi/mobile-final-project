import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/game_theme.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/widgets.dart';
import '../lobby/player_hub_navigation.dart';

/// `/profile` — the player's arena identity and account actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const path = '/profile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);

    return Theme(
      data: fantasySurfaceTheme(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _ProfileHeader(),
                Expanded(
                  child: me.when(
                    loading: () => const SingleChildScrollView(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: _ProfileSkeleton(),
                    ),
                    error: (_, __) => Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: FantasyPanel(
                        translucent: true,
                        child: ErrorView(
                          message: 'โหลดข้อมูลบัญชีไม่ได้ ลองอีกครั้ง',
                          onRetry: () => ref.invalidate(_meProvider),
                        ),
                      ),
                    ),
                    data: (user) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: _ProfileContent(user: user),
                        ),
                      ),
                    ),
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.profile),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(apiClientProvider).getMe();
});

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.huge,
              height: AppSpacing.huge,
              decoration: const BoxDecoration(
                color: Color(0x33FFD35A),
                borderRadius: AppRadius.allMd,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: Color(0xFFFFD35A),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'โปรไฟล์ผู้บัญชาการ',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFFFF5D6),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    'ข้อมูลบัญชีและตัวตนในสนามของคุณ',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final game = theme.extension<GameTheme>()!;
    final username = user['username'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final rating = user['rating'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FantasyPanel(
          translucent: true,
          child: Column(
            children: [
              CircleAvatar(
                radius: AppSpacing.huge,
                backgroundColor: const Color(0xFF243E85),
                foregroundColor: const Color(0xFFE4ECFF),
                child: Text(
                  _initials(username),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: Color(0x241BD7FF),
                  borderRadius: AppRadius.allFull,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.military_tech, color: game.gold),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'เรตติ้ง ${rating ?? '—'}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFFFD35A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FantasyPanel(
          translucent: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('บัญชีผู้ใช้', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: () => _editUsername(context, ref, username),
                child: const Text('แก้ไขชื่อผู้ใช้'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                variant: AppButtonVariant.danger,
                onPressed: () => _logout(context, ref),
                child: const Text('ออกจากระบบ'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppModal.confirm(
      context,
      title: 'ออกจากระบบ?',
      message: 'ต้องเข้าสู่ระบบใหม่เพื่อเล่นอีกครั้ง',
      confirmLabel: 'ออกจากระบบ',
      destructive: true,
    );
    if (!confirmed) return;
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
    final letters = parts.where((part) => part.isNotEmpty).take(2).map(
          (part) => part[0],
        );
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
  late final _controller = TextEditingController(text: widget.current);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final username = value.trim();
    if (username.isEmpty) return 'กรอกชื่อผู้ใช้';
    if (username.length < 3 || username.length > 20) {
      return 'ยาว 3–20 ตัวอักษร';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return 'ใช้ตัวอักษร ตัวเลข และ _ เท่านั้น';
    }
    return null;
  }

  Future<void> _save() async {
    final next = _controller.text.trim();
    final validation = _validate(next);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).updateMe(username: next);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (error) {
      setState(() {
        _error = error.response?.statusCode == 409
            ? 'ชื่อนี้ถูกใช้แล้ว'
            : 'บันทึกไม่สำเร็จ ลองอีกครั้ง';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'แก้ไขชื่อผู้ใช้',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'ชื่อผู้ใช้',
            controller: _controller,
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 240, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 144, radius: AppRadius.lg),
        ],
      );
}
