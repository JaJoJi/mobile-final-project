import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../lobby/player_hub_navigation.dart';
import '../player_hub/player_hub_models.dart';
import '../player_hub/player_hub_shell.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  static const path = '/rooms/create';

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  RoomViewState? _room;
  Map<String, dynamic>? _pendingRoomEvent;
  bool _loading = true;
  bool _opening = false;
  bool _leaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRoom());
  }

  Future<void> _openRoom({bool createIfMissing = true}) async {
    if (!mounted || _opening) return;
    _opening = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      Map<String, dynamic> json;
      try {
        json = await api.getMyRoom();
      } on DioException catch (error) {
        if (error.response?.statusCode != 404 || !createIfMissing) rethrow;
        if (ref.read(wsClientProvider).state != WsConnectionState.connected) {
          throw StateError('รอการเชื่อมต่อเกมแล้วลองอีกครั้ง');
        }
        json = await api.createRoom();
      }
      final userId = await ref.read(authRepositoryProvider).getUserId() ?? '';
      final me = await ref.read(apiClientProvider).getMe();
      if (!mounted) return;
      final room = RoomViewState.fromJson(
        json,
        currentUserId: userId,
        currentUsername: me['username'] as String? ?? 'คุณ',
      );
      setState(() => _room = room);
      final pending = _pendingRoomEvent;
      if (pending != null &&
          pending['roomId'] == room.roomId &&
          pending['status'] == 'matched' &&
          pending['matchId'] is String) {
        context.go('/match/${pending['matchId']}');
        return;
      }
      if (room.matchId != null) context.go('/match/${room.matchId}');
    } catch (error) {
      if (mounted) {
        if (!createIfMissing &&
            error is DioException &&
            error.response?.statusCode == 404) {
          setState(() {
            _room = null;
            _error = 'ห้องนี้สิ้นสุดแล้ว';
          });
          return;
        }
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : 'เปิดห้องไม่สำเร็จ ลองอีกครั้ง',
        );
      }
    } finally {
      _opening = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _leaveRoom() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await ref.read(apiClientProvider).leaveRoom();
      if (mounted) context.go('/lobby');
    } catch (_) {
      if (mounted) setState(() => _error = 'ออกจากห้องไม่สำเร็จ ลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FantasyPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppSpacing.huge + AppSpacing.lg,
                  height: AppSpacing.huge + AppSpacing.lg,
                  decoration: BoxDecoration(
                    color: const Color(0x26FF8E88),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xB3FF8E88)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40FF746D),
                        blurRadius: AppSpacing.lg,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFFFA19C),
                    size: AppSpacing.xxl,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'ออกจากห้องนี้?',
                  textAlign: TextAlign.center,
                  style:
                      Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFFFFF1C4),
                            fontWeight: FontWeight.w900,
                          ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'ห้องจะถูกยกเลิกและคุณจะกลับไปยังหน้าหลัก',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB8CEF0),
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('อยู่ในห้องต่อ'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE6817C),
                          foregroundColor: const Color(0xFF251112),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('ออกจากห้อง'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (leave == true && mounted) await _leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wsEventProvider('game:room:state'), (previous, next) {
      final json = next.valueOrNull;
      if (json == null) return;
      if (_room == null) {
        _pendingRoomEvent = json;
        return;
      }
      if (json['roomId'] != _room?.roomId) return;
      if (json['status'] == 'matched' && json['matchId'] is String) {
        context.go('/match/${json['matchId']}');
      } else if (json['status'] == 'closed') {
        context.go('/lobby');
      } else {
        _openRoom(createIfMissing: false);
      }
    });
    ref.listen(matchPhaseProvider, (previous, next) {
      final phase = next.valueOrNull;
      if (_room != null && phase != null) context.go('/match/${phase.matchId}');
    });
    ref.listen(wsConnectionStateProvider, (previous, next) {
      if (next.valueOrNull == WsConnectionState.connected &&
          previous?.valueOrNull == WsConnectionState.reconnecting) {
        _openRoom(createIfMissing: false);
      }
    });
    final online = ref.watch(wsConnectionStateProvider).valueOrNull ==
        WsConnectionState.connected;
    return PlayerHubShell(
      title: 'ห้องส่วนตัว',
      badge: '1 VS 1',
      lighter: true,
      headerLeading: IconButton(
        tooltip: 'ออกจากห้อง',
        onPressed: _room == null ? () => context.go('/lobby') : _confirmLeave,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      navigation: const PlayerHubNavigation(selected: PlayerHubTab.home),
      body: _loading && _room == null
          ? const Center(child: CircularProgressIndicator())
          : _room == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? 'ยังไม่มีห้อง'),
                      TextButton(
                        onPressed: () => _openRoom(),
                        child: const Text('ลองอีกครั้ง'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_error != null) Text(_error!),
                    if (!online)
                      const Text('ขาดการเชื่อมต่อ กำลังเชื่อมต่อใหม่…'),
                    Expanded(
                      child: RoomArenaContent(
                        room: _room!,
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Shared room presentation for the live room state.
class RoomArenaContent extends StatelessWidget {
  const RoomArenaContent({
    super.key,
    required this.room,
  });

  final RoomViewState room;

  @override
  Widget build(BuildContext context) {
    final isReconnecting = room.status == RoomFixtureStatus.reconnecting;
    final canAct = !isReconnecting;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          width: width,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? AppSpacing.md : AppSpacing.xl,
              AppSpacing.md,
              compact ? AppSpacing.md : AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    _InviteBar(room: room, canCopy: canAct),
                    const SizedBox(height: AppSpacing.lg),
                    _BattleStage(room: room, compact: compact),
                    const SizedBox(height: AppSpacing.lg),
                    _RoomStatus(room: room),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InviteBar extends StatelessWidget {
  const _InviteBar({required this.room, required this.canCopy});
  final RoomViewState room;
  final bool canCopy;

  @override
  Widget build(BuildContext context) => FantasyPanel(
        translucent: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: AppSpacing.huge + AppSpacing.sm,
              height: AppSpacing.huge + AppSpacing.sm,
              decoration: const BoxDecoration(
                color: Color(0x1FF2C14E),
                borderRadius: AppRadius.allMd,
              ),
              child: const Icon(
                Icons.vpn_key_rounded,
                color: Color(0xFFFFD35A),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รหัสห้อง',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF8AD6FF),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  SelectableText(
                    room.roomCode,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFFFD35A),
                          letterSpacing: 3,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: 'คัดลอกรหัสห้อง',
              onPressed: canCopy
                  ? () async {
                      await Clipboard.setData(
                        ClipboardData(text: room.roomCode),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('คัดลอกรหัสแล้ว')),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.copy_rounded),
            ),
          ],
        ),
      );
}

class _BattleStage extends StatelessWidget {
  const _BattleStage({required this.room, required this.compact});
  final RoomViewState room;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final guest = room.guest;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xE6254562),
            Color(0xF20B1C2C),
            Color(0xE646252F),
          ],
          stops: [0, .5, 1],
        ),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: const Color(0x6659B7E8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D59B7E8),
            blurRadius: AppSpacing.lg,
            offset: Offset(-AppSpacing.xs, AppSpacing.xs),
          ),
          BoxShadow(
            color: Color(0x40FF746D),
            blurRadius: AppSpacing.lg,
            offset: Offset(AppSpacing.xs, AppSpacing.xs),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Divider(color: Color(0x8070D7FF)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  compact ? 'สนามดวล · 1 VS 1' : 'เตรียมเข้าสู่สนาม · 1 VS 1',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFFFFE5A4),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const Expanded(
                child: Divider(color: Color(0x80FF8E88)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PlayerSide(
                  player: room.host,
                  enemy: false,
                  compact: compact,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? AppSpacing.xs : AppSpacing.md,
                ),
                child: _VersusBadge(compact: compact),
              ),
              Expanded(
                child: _PlayerSide(
                  player: guest,
                  enemy: true,
                  compact: compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersusBadge extends StatelessWidget {
  const _VersusBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: compact ? AppSpacing.huge : AppSpacing.huge + AppSpacing.sm,
        height: compact ? AppSpacing.huge : AppSpacing.huge + AppSpacing.sm,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF111B2A),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF2C14E), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x5559B7E8),
              blurRadius: AppSpacing.md,
              offset: Offset(-AppSpacing.xs, 0),
            ),
            BoxShadow(
              color: Color(0x55FF746D),
              blurRadius: AppSpacing.md,
              offset: Offset(AppSpacing.xs, 0),
            ),
          ],
        ),
        child: Text(
          'VS',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFFFD35A),
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
              ),
        ),
      );
}

class _PlayerSide extends StatelessWidget {
  const _PlayerSide({
    required this.player,
    required this.enemy,
    required this.compact,
  });

  final RoomPlayer? player;
  final bool enemy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final player = this.player;
    final accent = enemy ? const Color(0xFFFF8E88) : const Color(0xFF70D7FF);
    final avatarSize = compact ? 72.0 : 92.0;
    return Column(
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: player == null
                  ? const [Color(0xFF202938), Color(0xFF101722)]
                  : enemy
                      ? const [Color(0xFF49252B), Color(0xFF171622)]
                      : const [Color(0xFF214C70), Color(0xFF172454)],
            ),
            border: Border.all(color: accent, width: 2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .28),
                blurRadius: AppSpacing.lg,
              ),
            ],
          ),
          child: Text(
            player?.crestLabel ?? '?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: player == null
                      ? const Color(0xFF8090A3)
                      : const Color(0xFFF4F7FF),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          player?.username ?? 'รอผู้ท้าชิง',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .09),
            borderRadius: AppRadius.allFull,
            border: Border.all(color: accent.withValues(alpha: .38)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!enemy && player != null) ...[
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: AppSpacing.lg,
                  color: Color(0xFFFFD35A),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  player?.roleLabel ?? 'ยังไม่มีผู้เล่น',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            player == null ? const Color(0xFF91A2B8) : accent,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomStatus extends StatelessWidget {
  const _RoomStatus({required this.room});
  final RoomViewState room;

  @override
  Widget build(BuildContext context) {
    final title = switch (room.status) {
      RoomFixtureStatus.waiting => 'กำลังรอผู้ท้าชิง',
      RoomFixtureStatus.joined => 'ผู้ท้าชิงเข้าร่วมแล้ว',
      RoomFixtureStatus.reconnecting => 'กำลังเชื่อมต่อใหม่',
    };
    final description = switch (room.status) {
      RoomFixtureStatus.waiting => 'ส่งรหัสห้องให้เพื่อนเพื่อเริ่มการแข่งขัน',
      RoomFixtureStatus.joined => 'กำลังเตรียมการแข่งขัน',
      RoomFixtureStatus.reconnecting => 'รอสถานะล่าสุดจากเซิร์ฟเวอร์',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xD928352E), Color(0xE60D2132)],
        ),
        borderRadius: AppRadius.allLg,
        border: Border.all(color: const Color(0x80F2C14E)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33F2C14E),
            blurRadius: AppSpacing.lg,
          ),
        ],
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppSpacing.huge,
              height: AppSpacing.huge,
              decoration: const BoxDecoration(
                color: Color(0x1FF2C14E),
                borderRadius: AppRadius.allMd,
              ),
              child: switch (room.status) {
                RoomFixtureStatus.waiting => const _WaitingHourglass(),
                RoomFixtureStatus.joined => const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF67D9A4),
                  ),
                RoomFixtureStatus.reconnecting => const Icon(
                    Icons.sync_rounded,
                    color: Color(0xFF8AD6FF),
                  ),
              },
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFFFE5A4),
                        ),
                  ),
                  Text(description, textAlign: TextAlign.start),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingHourglass extends StatefulWidget {
  const _WaitingHourglass();

  @override
  State<_WaitingHourglass> createState() => _WaitingHourglassState();
}

class _WaitingHourglassState extends State<_WaitingHourglass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController.unbounded(vsync: this);
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    _pauseTimer = Timer(const Duration(milliseconds: 600), _flip);
  }

  Future<void> _flip() async {
    await _controller.animateTo(
      _controller.value + 0.5,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    _pauseTimer = Timer(const Duration(milliseconds: 900), _flip);
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        key: const ValueKey('waiting-hourglass-rotation'),
        turns: _controller,
        child: const Icon(
          Icons.hourglass_top_rounded,
          color: Color(0xFFFFD35A),
        ),
      );
}
