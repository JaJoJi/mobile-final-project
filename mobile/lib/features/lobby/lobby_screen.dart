import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/game_art_frame.dart';
import '../../core/widgets/state_views.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';
import '../history/history_format.dart';
import '../history/history_providers.dart';
import '../history/match_models.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../rooms/create_room_screen.dart';
import '../rooms/join_room_screen.dart';
import 'find_match_button.dart';
import 'matchmaking_state.dart';
import 'player_hub_header.dart';
import 'player_hub_navigation.dart';

/// The authenticated Player Hub and primary entry point for matchmaking.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  static const path = '/lobby';
  static const _navDelay = Duration(milliseconds: 500);

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
        ref.read(matchmakingStateProvider.notifier).resetAfterMatch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<MatchPhaseEvent>>(matchPhaseProvider, (prev, next) {
      final phase = next.valueOrNull;
      if (phase == null) return;
      final state = ref.read(matchmakingStateProvider);
      if (state != MatchmakingState.joining &&
          state != MatchmakingState.searching) {
        return;
      }
      _onMatchFound(phase);
    });

    final state = ref.watch(matchmakingStateProvider);
    final wsState = ref.watch(wsConnectionStateProvider);
    final connectionStatus = switch (wsState.valueOrNull) {
      WsConnectionState.connected => ConnectionStatus.connected,
      WsConnectionState.connecting => ConnectionStatus.connecting,
      WsConnectionState.reconnecting => ConnectionStatus.reconnecting,
      WsConnectionState.disconnected => ConnectionStatus.disconnected,
      null => ConnectionStatus.connected,
    };

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
                const PlayerHubHeader(),
                ConnectionBanner(status: connectionStatus, onRetry: () {}),
                Expanded(
                  child: _HomeFeed(
                    state: state,
                    matchmakingEnabled:
                        connectionStatus == ConnectionStatus.connected,
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.home),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMatchFound(MatchPhaseEvent phase) async {
    if (_navigating) return;
    _navigating = true;
    ref.read(matchmakingStateProvider.notifier).markMatched();
    if (mounted) {
      AppToast.show(
        context,
        'พบคู่แข่งแล้ว!',
        variant: AppToastVariant.success,
      );
    }
    await Future<void>.delayed(LobbyScreen._navDelay);
    if (mounted) context.go('/match/${phase.matchId}');
  }
}

class _HomeFeed extends StatelessWidget {
  const _HomeFeed({required this.state, required this.matchmakingEnabled});

  final MatchmakingState state;
  final bool matchmakingEnabled;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlayCard(
                  state: state,
                  matchmakingEnabled: matchmakingEnabled,
                ),
                const SizedBox(height: AppSpacing.lg),
                const _LeaderboardPreview(),
                const SizedBox(height: AppSpacing.lg),
                const _RecentMatchPreview(),
              ],
            ),
          ),
        ),
      );
}

class _PlayCard extends StatelessWidget {
  const _PlayCard({required this.state, required this.matchmakingEnabled});

  final MatchmakingState state;
  final bool matchmakingEnabled;

  @override
  Widget build(BuildContext context) => FantasyPanel(
        translucent: true,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => AspectRatio(
                aspectRatio: constraints.maxWidth < 500 ? 1.65 : 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      GameBackgroundAssets.homeTeamBanner,
                      key: const ValueKey('home-team-banner'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xE60A1B2B),
                            Color(0x8C0A1B2B),
                            Color(0x000A1B2B),
                          ],
                          stops: [0, 0.42, 0.7],
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      child: _MatchmakingTimerBadge(state: state),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.43,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ออโต้เชส',
                                maxLines: 1,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: const Color(0xFFFFD867),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'เข้าสู่สนาม',
                                  maxLines: 1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        color: const Color(0xFFFFF5D6),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'วางแผน · ปรับตัว · อยู่รอด',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: const Color(0xFFD7E8FF)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FindMatchButton(enabled: matchmakingEnabled),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.go(CreateRoomScreen.path),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('สร้างห้อง'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.go(JoinRoomScreen.path),
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('เข้าร่วมห้อง'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _LeaderboardPreview extends StatelessWidget {
  const _LeaderboardPreview();

  @override
  Widget build(BuildContext context) => FantasyPanel(
        translucent: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: 'อันดับประจำฤดูกาล',
              onPressed: () => _comingSoon(context, 'ตารางอันดับ'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  color: Color(0xFFFFD35A),
                  size: AppSpacing.xxl,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ตารางอันดับกำลังจะเปิดใช้งาน',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        'ยังไม่มีข้อมูลอันดับประจำฤดูกาลในขณะนี้',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RecentMatchPreview extends ConsumerWidget {
  const _RecentMatchPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(matchHistoryProvider);
    return FantasyPanel(
      translucent: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'การแข่งขันล่าสุด',
            onPressed: () => context.go('/history'),
          ),
          const SizedBox(height: AppSpacing.sm),
          history.when(
            loading: () => const SkeletonBox(height: 72),
            error: (_, __) => Row(
              children: [
                const Expanded(child: Text('โหลดการแข่งขันล่าสุดไม่สำเร็จ')),
                TextButton(
                  onPressed: () => ref.invalidate(matchHistoryProvider),
                  child: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
            data: (matches) => matches.isEmpty
                ? const Text(
                    'ยังไม่มีการแข่งขัน ผลล่าสุดจะแสดงที่นี่',
                  )
                : _RecentMatchRow(entry: matches.first),
          ),
        ],
      ),
    );
  }
}

class _RecentMatchRow extends StatelessWidget {
  const _RecentMatchRow({required this.entry});

  final MatchHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (entry.outcome) {
      MatchOutcome.win => (
          'ชนะ',
          const Color(0xFF62E8B3),
          Icons.emoji_events_outlined,
        ),
      MatchOutcome.loss => (
          'แพ้',
          Theme.of(context).colorScheme.error,
          Icons.close_rounded,
        ),
      MatchOutcome.tie => (
          'เสมอ',
          Theme.of(context).colorScheme.onSurfaceVariant,
          Icons.remove_rounded,
        ),
    };
    final opponent = entry.opponentName ?? 'ผู้เล่นที่ลบบัญชี';

    return Semantics(
      button: true,
      label: '$label พบ $opponent',
      child: InkWell(
        onTap: () => context.push('/history/${entry.matchId}'),
        borderRadius: AppRadius.allMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: AppSpacing.huge,
                height: AppSpacing.huge,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.allMd,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: color, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'พบ $opponent · ${entry.rounds} รอบ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${relativeThai(entry.createdAt)}ที่แล้ว',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFD8E7FF),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: AppRadius.allSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ดูทั้งหมด',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: const Color(0xFFFFD35A),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Color(0xFFFFD35A),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

class _MatchmakingTimerBadge extends StatefulWidget {
  const _MatchmakingTimerBadge({required this.state});

  final MatchmakingState state;

  @override
  State<_MatchmakingTimerBadge> createState() => _MatchmakingTimerBadgeState();
}

class _MatchmakingTimerBadgeState extends State<_MatchmakingTimerBadge> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  bool get _active => widget.state != MatchmakingState.idle;

  @override
  void initState() {
    super.initState();
    if (_active) _start();
  }

  @override
  void didUpdateWidget(covariant _MatchmakingTimerBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.state != MatchmakingState.idle;
    if (!wasActive && _active) {
      _start();
    } else if (wasActive && !_active) {
      _stop();
    }
  }

  void _start() {
    _ticker?.cancel();
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _elapsed = Duration(seconds: timer.tick));
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _elapsed = Duration.zero;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();

    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final (label, color) = switch (widget.state) {
      MatchmakingState.idle => ('', const Color(0xFFFFD35A)),
      MatchmakingState.joining => ('กำลังเข้าคิว', const Color(0xFF77D8FF)),
      MatchmakingState.searching => ('กำลังค้นหา', const Color(0xFFFFD35A)),
      MatchmakingState.matched => ('พบคู่แข่งแล้ว', const Color(0xFF67D9A4)),
    };

    return Semantics(
      key: const ValueKey('matchmaking-timer-badge'),
      liveRegion: true,
      label: '$label $minutes นาที $seconds วินาที',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE60A1B2B),
          borderRadius: AppRadius.allFull,
          border: Border.all(color: color.withValues(alpha: 0.65)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: AppSpacing.sm),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.state == MatchmakingState.matched)
              Icon(Icons.check_circle_rounded, size: 16, color: color)
            else
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: AppSpacing.xxs,
                  color: color,
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFFFFF5D6),
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _comingSoon(BuildContext context, String feature) {
  AppToast.show(context, '$feature จะเปิดให้ใช้งานเร็ว ๆ นี้');
}
