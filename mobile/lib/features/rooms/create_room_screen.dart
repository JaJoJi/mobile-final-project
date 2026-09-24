import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../player_hub/player_crest.dart';
import '../player_hub/player_hub_fixture_provider.dart';
import '../player_hub/player_hub_models.dart';
import '../player_hub/player_hub_shell.dart';
import '../profile/player_hub_navigation.dart';

class CreateRoomScreen extends ConsumerWidget {
  const CreateRoomScreen({super.key});

  static const path = '/rooms/create';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomFixtureProvider);
    return PlayerHubShell(
      title: 'ห้องส่วนตัว',
      subtitle: 'ออโต้เชส / ประลองกับเพื่อน',
      headerAction: _ConnectionLabel(status: room.status),
      navigation: const PlayerHubNavigation(),
      body: RoomArenaContent(room: room),
    );
  }
}

/// The fixture-only online-room presentation shared by host and join preview.
class RoomArenaContent extends StatelessWidget {
  const RoomArenaContent({super.key, required this.room});

  final RoomViewState room;

  @override
  Widget build(BuildContext context) {
    final isJoined = room.status == RoomFixtureStatus.joined;
    final isReconnecting = room.status == RoomFixtureStatus.reconnecting;
    final canAct = !isJoined && !isReconnecting;
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
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xD90B1C2C),
                border: Border.all(color: const Color(0x66829EB2)),
                borderRadius: AppRadius.allMd,
                image: const DecorationImage(
                  image: AssetImage(
                    'assets/images/backgrounds/arena_background_landscape.webp',
                  ),
                  fit: BoxFit.cover,
                  opacity: .20,
                ),
              ),
              child: Column(
                children: [
                  _InviteBar(room: room, canCopy: canAct),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? AppSpacing.sm : AppSpacing.xl,
                      AppSpacing.lg,
                      compact ? AppSpacing.sm : AppSpacing.xl,
                      0,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'เตรียมเข้าสู่สนาม',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              'ผู้เล่น ${room.guest == null ? 1 : 2} / 2',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _BattleStage(room: room, compact: compact),
                      ],
                    ),
                  ),
                  _RoomStatus(room: room),
                  _RoomFooter(
                    canCancel: canAct,
                    onCancel: () => _confirmLeave(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยกเลิกห้องตัวอย่างนี้?'),
        content: const Text('ออกจากห้องเพื่อกลับหน้าหลัก'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('อยู่ในห้องต่อ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยกเลิกห้อง'),
          ),
        ],
      ),
    );
    if (leave == true && context.mounted) context.go('/lobby');
  }
}

class _InviteBar extends StatelessWidget {
  const _InviteBar({required this.room, required this.canCopy});
  final RoomViewState room;
  final bool canCopy;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: Color(0xCC071322),
          border: Border(bottom: BorderSide(color: Color(0x44829EB2))),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AppSpacing.xs,
          spacing: AppSpacing.md,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                const Text('รหัสห้อง'),
                SelectableText(
                  room.roomCode,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                OutlinedButton.icon(
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
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('คัดลอก'),
                ),
              ],
            ),
            const Text('2 ผู้เล่น · เริ่มอัตโนมัติ'),
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
    return Row(
      children: [
        Expanded(
          child: _PlayerSide(
            player: room.host,
            side: 'ฝั่งคุณ',
            enemy: false,
            compact: compact,
          ),
        ),
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 0 : AppSpacing.md),
          child: Column(
            children: [
              Container(
                width: 1,
                height: compact ? 24 : 48,
                color: const Color(0x99D5BB76),
              ),
              Text(
                'VS',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFFFFE5A4),
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                    ),
              ),
              Container(
                width: 1,
                height: compact ? 24 : 48,
                color: const Color(0x99D5BB76),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PlayerSide(
            player: guest,
            side: 'ผู้ท้าชิง',
            enemy: true,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _PlayerSide extends StatelessWidget {
  const _PlayerSide({
    required this.player,
    required this.side,
    required this.enemy,
    required this.compact,
  });

  final RoomPlayer? player;
  final String side;
  final bool enemy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final player = this.player;
    final accent = enemy ? const Color(0xFFFFAB99) : const Color(0xFF7ED8FF);
    return Column(
      children: [
        Text(
          side,
          style: TextStyle(
            color: accent,
            fontSize: 12,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: compact ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Opacity(
            opacity: player == null ? .56 : 1,
            child:
                PlayerCrest(label: player?.crestLabel ?? '?', compact: compact),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: enemy ? const Color(0xCC30232C) : const Color(0xCC193A55),
            border: Border(
              top: BorderSide(color: accent, width: 2),
              bottom: BorderSide(
                color: accent.withValues(
                  alpha: .35,
                ),
              ),
            ),
          ),
          child: Column(
            children: [
              Text(
                player?.username ?? 'รอคู่แข่ง',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                player?.roleLabel ?? 'ส่งรหัสห้องให้เพื่อน',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
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
      RoomFixtureStatus.joined => 'กำลังเข้าสู่สนาม',
      RoomFixtureStatus.reconnecting => 'กำลังเชื่อมต่อใหม่',
    };
    final description = switch (room.status) {
      RoomFixtureStatus.waiting =>
        'เมื่อเพื่อนเข้าร่วม ทั้งสองคนจะเข้าสู่เกมอัตโนมัติ',
      RoomFixtureStatus.joined => 'พบคู่แข่งแล้ว รอระบบพาทั้งสองคนเข้าเกม',
      RoomFixtureStatus.reconnecting =>
        'ห้องยังแสดงข้อมูลล่าสุด รอยืนยันสถานะจากระบบ',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.diamond_outlined, color: Color(0xFFF2C14E)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFFFE5A4),
                        ),
                  ),
                  Text(description, textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFooter extends StatelessWidget {
  const _RoomFooter({required this.canCancel, required this.onCancel});
  final bool canCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: Color(0xCC080F1B),
          border: Border(top: BorderSide(color: Color(0x44829EB2))),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AppSpacing.sm,
          spacing: AppSpacing.md,
          children: [
            const Text('ห้องของ JaJoJi\nออกจากห้องเพื่อกลับหน้าหลัก'),
            OutlinedButton(
              onPressed: canCancel ? onCancel : null,
              child: const Text('ยกเลิกห้อง'),
            ),
          ],
        ),
      );
}

class _ConnectionLabel extends StatelessWidget {
  const _ConnectionLabel({required this.status});
  final RoomFixtureStatus status;

  @override
  Widget build(BuildContext context) {
    final reconnecting = status == RoomFixtureStatus.reconnecting;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 9,
          color:
              reconnecting ? const Color(0xFFF2C14E) : const Color(0xFFA1E5C1),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(reconnecting ? 'กำลังเชื่อมต่อใหม่' : 'เชื่อมต่อแล้ว'),
      ],
    );
  }
}
