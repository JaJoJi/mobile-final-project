import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/widgets.dart';
import '../lobby/logout_button.dart';
import '../lobby/player_hub_navigation.dart';
import '../lobby/profile_card.dart';
import 'settings_provider.dart';
import 'settings_tile.dart';

/// `/profile` — account info + settings + logout. Design spec §4.8, P1-FE-02.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const path = '/profile';
  static const _appVersion = '0.1.0+1'; // keep in sync with pubspec

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final statistics = ref.watch(_myStatsProvider);

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
                          onRetry: () => ref.invalidate(currentUserProvider),
                        ),
                      ),
                    ),
                    data: (u) => Column(
                      children: [
                        _ProfileHero(
                          user: u,
                          statistics: statistics,
                          onEdit: () => _editUsername(
                            context,
                            ref,
                            u['username'] as String? ?? '',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.xs,
                              AppSpacing.lg,
                              AppSpacing.xl,
                            ),
                            child: _Content(),
                          ),
                        ),
                      ],
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

/// Statistics are deliberately independent from the account request: profile
/// actions remain available if the optional statistics endpoint is unavailable.
final _myStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.read(apiClientProvider).getMyStats();
});

Future<void> _editUsername(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final saved = await AppModal.sheet<bool>(
    context,
    builder: (_) => _EditUsernameSheet(current: current),
  );
  if (saved == true) ref.invalidate(currentUserProvider);
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.statistics,
    required this.onEdit,
  });

  final Map<String, dynamic> user;
  final AsyncValue<Map<String, dynamic>> statistics;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final rating = (user['rating'] as num?)?.round();
    final statisticsValue = statistics.valueOrNull;
    final currentRank = statisticsValue?['currentRank'];
    final rankLabel = statisticsValue == null
        ? 'อันดับ —'
        : currentRank == null
            ? 'ยังไม่มีอันดับ'
            : 'อันดับ $currentRank';

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        key: const ValueKey('profile-hero'),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xE61B425A), Color(0xF20A1B2E)],
          ),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: const Color(0x9959B7E8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: AppSpacing.xl,
              offset: Offset(0, AppSpacing.sm),
            ),
            BoxShadow(
              color: Color(0x2459B7E8),
              blurRadius: AppSpacing.lg,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF355AA8), Color(0xFF182A68)],
                    ),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xB39DDCFF), width: 2),
                    ),
                  ),
                  child: Text(
                    _initials(username),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFD7E8FF),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'แก้ไขชื่อผู้ใช้',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0x66101F31),
                    side: const BorderSide(color: Color(0x406FA5C4)),
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.military_tech_rounded,
                    label: rating == null
                        ? 'เรตติ้ง —'
                        : 'เรตติ้ง ${_formatNumber(rating)}',
                    color: const Color(0xFFFFD35A),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _HeroMetric(
                    key: const ValueKey('profile-rank-action'),
                    icon: Icons.emoji_events_rounded,
                    label: rankLabel,
                    color: const Color(0xFF9DDCFF),
                    onTap: () => context.go('/leaderboard'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(
                  child: LogoutButton(showLabel: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
  }

  static String _formatNumber(int value) => value.toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+$)'),
        (_) => ',',
      );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allFull,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: const Color(0xB3071726),
              borderRadius: AppRadius.allFull,
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.chevron_right_rounded, size: 17, color: color),
                ],
              ],
            ),
          ),
        ),
      );
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final stats = ref.watch(_myStatsProvider);

    return _ProfileDetails(
      statistics: stats,
      themeMode: settings.themeMode,
      soundEnabled: settings.soundEnabled,
      autoReconnect: settings.wsAutoReconnect,
      onThemeChanged: (mode) => settingsNotifier.setThemeMode(mode),
      onSoundChanged: settingsNotifier.setSoundEnabled,
      onReconnectChanged: settingsNotifier.setWsAutoReconnect,
      onRetryStats: () => ref.invalidate(_myStatsProvider),
    );
  }
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
  });

  final AsyncValue<Map<String, dynamic>> statistics;
  final ThemeMode themeMode;
  final bool soundEnabled;
  final bool autoReconnect;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<bool> onReconnectChanged;
  final VoidCallback onRetryStats;

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
          FantasyPanel(
            translucent: true,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF9DDCFF),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'ตั้งค่า',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0x406FA5C4)),
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
                const Divider(color: Color(0x406FA5C4)),
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
                  color: const Color(0xFFF4F7FB),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            SizedBox(
              width: itemWidth,
              child: _Statistic(
                value: '$matches',
                label: 'แข่งขัน',
                icon: Icons.sports_esports_rounded,
                accent: const Color(0xFF9DDCFF),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Statistic(
                value: '$wins',
                label: 'ชนะ',
                icon: Icons.emoji_events_rounded,
                accent: const Color(0xFF67DDA8),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Statistic(
                value: '$losses',
                label: 'แพ้',
                icon: Icons.heart_broken_rounded,
                accent: const Color(0xFFFF8A8A),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _Statistic(
                value: winRate == null ? '—' : '$winRate%',
                label: 'อัตราชนะ',
                icon: Icons.insights_rounded,
                accent: const Color(0xFFFFD35A),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Statistic extends StatelessWidget {
  const _Statistic({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: const Color(0xB30A1B2E),
          borderRadius: AppRadius.allMd,
          border: Border.all(color: accent.withValues(alpha: 0.38)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB8CEF0),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
