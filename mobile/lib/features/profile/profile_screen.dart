import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_gate.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/widgets.dart';
import '../player_hub/player_crest.dart';
import '../player_hub/player_hub_shell.dart';
import 'player_hub_navigation.dart';
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

    return PlayerHubShell(
      title: 'โปรไฟล์ผู้บัญชาการ',
      subtitle: 'ตัวตนและผลงานในสนาม',
      badge: 'บัญชีของคุณ',
      body: me.when(
        loading: () => const SingleChildScrollView(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: _ProfileSkeleton(),
        ),
        error: (_, __) => ErrorView(
          message: 'โหลดข้อมูลบัญชีไม่ได้ ลองอีกครั้ง',
          onRetry: () => ref.invalidate(_meProvider),
        ),
        data: (u) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _Content(user: u),
        ),
      ),
      navigation: const PlayerHubNavigation(),
    );
  }
}

/// `GET /user/me` → `{ id, email, username, rating }`.
final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(apiClientProvider).getMe();
});

/// Statistics are deliberately independent from the account request: profile
/// actions remain available if the optional statistics endpoint is unavailable.
final _myStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(apiClientProvider).getMyStats();
});

class _Content extends ConsumerWidget {
  const _Content({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final stats = ref.watch(_myStatsProvider);

    final username = user['username'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final rating = user['rating'];

    final identity = _IdentityPanel(
      username: username,
      email: email,
      rating: rating,
      initials: _initials(username),
      onEdit: () => _editUsername(context, ref, username),
    );
    final details = _ProfileDetails(
      statistics: stats,
      themeMode: settings.themeMode,
      soundEnabled: settings.soundEnabled,
      autoReconnect: settings.wsAutoReconnect,
      onThemeChanged: (mode) => settingsNotifier.setThemeMode(mode),
      onSoundChanged: settingsNotifier.setSoundEnabled,
      onReconnectChanged: settingsNotifier.setWsAutoReconnect,
      onRetryStats: () => ref.invalidate(_myStatsProvider),
      onLogout: () => _logout(context, ref),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 276, child: identity),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: details),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [identity, const SizedBox(height: AppSpacing.lg), details],
        );
      },
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

class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({
    required this.username,
    required this.email,
    required this.rating,
    required this.initials,
    required this.onEdit,
  });

  final String username;
  final String email;
  final Object? rating;
  final String initials;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => FantasyPanel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 480;
            final details = _IdentityDetails(
              username: username,
              email: email,
              rating: _formatRating(rating),
              compact: compact,
              onEdit: onEdit,
            );
            if (!compact) {
              return Column(
                children: [
                  PlayerCrest(label: initials),
                  const SizedBox(height: AppSpacing.md),
                  details,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlayerCrest(label: initials, compact: true),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: details),
              ],
            );
          },
        ),
      );

  static String _formatRating(Object? rating) {
    final raw = rating?.toString();
    final value = raw == null ? null : num.tryParse(raw)?.round();
    if (value == null) return '—';
    return value.toString().replaceAllMapped(
          RegExp(r'(?<=\d)(?=(\d{3})+$)'),
          (_) => ',',
        );
  }
}

class _IdentityDetails extends StatelessWidget {
  const _IdentityDetails({
    required this.username,
    required this.email,
    required this.rating,
    required this.compact,
    required this.onEdit,
  });

  final String username;
  final String email;
  final String rating;
  final bool compact;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.xl),
          Text(
            rating,
            style: (compact
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.displaySmall)
                ?.copyWith(
              color: const Color(0xFFF2C14E),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'เรตติ้งปัจจุบัน',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
          OutlinedButton(
            onPressed: onEdit,
            child: const Text('แก้ไขชื่อผู้ใช้'),
          ),
        ],
      );
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({
    required this.statistics,
    required this.themeMode,
    required this.soundEnabled,
    required this.autoReconnect,
    required this.onThemeChanged,
    required this.onSoundChanged,
    required this.onReconnectChanged,
    required this.onRetryStats,
    required this.onLogout,
  });

  final AsyncValue<Map<String, dynamic>> statistics;
  final ThemeMode themeMode;
  final bool soundEnabled;
  final bool autoReconnect;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<bool> onReconnectChanged;
  final VoidCallback onRetryStats;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(
            title: 'บันทึกการประลอง',
            subtitle: 'แมตช์ที่จบแล้ว',
          ),
          const SizedBox(height: AppSpacing.sm),
          statistics.when(
            loading: () => const SkeletonBox(height: 154, radius: AppRadius.md),
            error: (_, __) => FantasyPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('โหลดสถิติการแข่งขันไม่ได้'),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: onRetryStats,
                    child: const Text('ลองอีกครั้ง'),
                  ),
                ],
              ),
            ),
            data: (data) => _StatisticsCard(statistics: data),
          ),
          const SizedBox(height: AppSpacing.lg),
          _RankBanner(statistics: statistics),
          const SizedBox(height: AppSpacing.lg),
          FantasyPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ทุกแมตช์คือประสบการณ์',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'ย้อนดูผลการแข่งขันและรอบที่จบในแต่ละเกม',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => context.go('/history'),
                  child: const Text('ดูประวัติการแข่งขัน'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            key: const ValueKey('private-account-row'),
            padding: const EdgeInsets.only(top: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x4D82A9C7))),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  'ข้อมูลบัญชีเป็นส่วนตัว',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('ออกจากระบบ'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FantasyPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ตั้งค่า', style: Theme.of(context).textTheme.titleLarge),
                const Divider(),
                SettingsTile(
                  leading: Icons.brightness_6_outlined,
                  title: 'ธีม',
                  stackTrailing: true,
                  trailing: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('ระบบ'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('สว่าง'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('มืด'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) => onThemeChanged(s.first),
                    ),
                  ),
                ),
                SettingsTile(
                  leading: Icons.wifi_tethering,
                  title: 'เชื่อมต่อใหม่อัตโนมัติ',
                  subtitle: 'ต่อ WebSocket ใหม่เองเมื่อสัญญาณหลุด',
                  trailing: Switch(
                    value: autoReconnect,
                    onChanged: onReconnectChanged,
                  ),
                ),
                SettingsTile(
                  leading: soundEnabled
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
                  title: 'เสียงเอฟเฟกต์',
                  subtitle: 'เสียงซื้อ รีเฟรช และกดพร้อม',
                  trailing: Switch(
                    value: soundEnabled,
                    onChanged: onSoundChanged,
                  ),
                ),
                const Divider(),
                const SettingsTile(
                  leading: Icons.info_outline,
                  title: 'เวอร์ชัน',
                  trailing: Text(ProfileScreen._appVersion),
                ),
              ],
            ),
          ),
        ],
      );
}

class _RankBanner extends StatelessWidget {
  const _RankBanner({required this.statistics});

  final AsyncValue<Map<String, dynamic>> statistics;

  @override
  Widget build(BuildContext context) {
    final rank = statistics.valueOrNull?['currentRank'];
    final matches = statistics.valueOrNull?['matches'] ?? 0;
    return Container(
      key: const ValueKey('profile-rank-banner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x8866532B), Color(0xDD14263A)],
        ),
        border: Border(left: BorderSide(color: Color(0xFFF2C14E), width: 3)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'อันดับปัจจุบัน',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  rank == null ? 'ยังไม่มีอันดับ' : 'อันดับ #$rank',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFFF2C14E),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'บนตารางอันดับ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (matches == 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'ลงสนามครั้งแรกเพื่อเริ่มบันทึกสถิติ',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
            FilledButton(
              onPressed: () => context.go('/leaderboard'),
              child: const Text('ดูตารางอันดับ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.statistics});

  final Map<String, dynamic> statistics;

  @override
  Widget build(BuildContext context) {
    final matches = statistics['matches'] ?? 0;
    final wins = statistics['wins'] ?? 0;
    final losses = statistics['losses'] ?? 0;
    final winRate = statistics['winRate'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: const BoxDecoration(
            color: Color(0xE60E2438),
            border: Border(
              top: BorderSide(color: Color(0xFF739ABD), width: 2),
              bottom: BorderSide(color: Color(0x6682A9C7)),
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.md,
            children: [
              _Statistic(value: '$matches', label: 'แข่งขัน'),
              _Statistic(value: '$wins', label: 'ชนะ'),
              _Statistic(value: '$losses', label: 'แพ้'),
              _Statistic(
                value: winRate == null ? '—' : '$winRate%',
                label: 'อัตราชนะ',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Statistic extends StatelessWidget {
  const _Statistic({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
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
