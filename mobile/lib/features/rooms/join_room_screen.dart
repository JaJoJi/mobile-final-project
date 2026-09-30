import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../player_hub/player_hub_shell.dart';
import '../profile/player_hub_navigation.dart';
import 'create_room_screen.dart';

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  static const path = '/rooms/join';

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _joining = false;

  String get _normalizedCode =>
      _codeController.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wsEventProvider('game:room:state'), (previous, next) {
      final event = next.valueOrNull;
      if (event?['status'] == 'matched' && event?['matchId'] is String) {
        context.go('/match/${event!['matchId']}');
      }
    });
    final online = ref.watch(wsConnectionStateProvider).valueOrNull ==
        WsConnectionState.connected;
    return PlayerHubShell(
      title: 'เข้าร่วมห้อง',
      subtitle: 'พบเพื่อนในสนามส่วนตัว',
      badge: '1 vs 1',
      navigation: const PlayerHubNavigation(),
      body: _buildJoinForm(context, online),
    );
  }

  Widget _buildJoinForm(BuildContext context, bool online) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          return SingleChildScrollView(
            padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
            child: compact
                ? Column(
                    children: [
                      const _ChallengerArt(compact: true),
                      const SizedBox(height: AppSpacing.md),
                      _JoinForm(
                        controller: _codeController,
                        error: _error,
                        onCodeChanged: _onCodeChanged,
                        onJoin: _join,
                        joining: _joining,
                        online: online,
                        onCreateRoom: () => context.go(CreateRoomScreen.path),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(child: _ChallengerArt()),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(
                        child: _JoinForm(
                          controller: _codeController,
                          error: _error,
                          onCodeChanged: _onCodeChanged,
                          onJoin: _join,
                          joining: _joining,
                          online: online,
                          onCreateRoom: () => context.go(CreateRoomScreen.path),
                        ),
                      ),
                    ],
                  ),
          );
        },
      );

  void _onCodeChanged(String _) {
    setState(() => _error = null);
  }

  Future<void> _join() async {
    if (_joining) return;
    final code = _normalizedCode;
    _codeController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(code)) {
      setState(() => _error = 'รหัสห้องต้องมี 6 ตัวอักษร A-Z หรือเลข 2-9');
      return;
    }
    if (ref.read(wsClientProvider).state != WsConnectionState.connected) {
      setState(
        () => _error = 'ขาดการเชื่อมต่อเกม ลองอีกครั้งเมื่อเชื่อมต่อแล้ว',
      );
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final room = await ref.read(apiClientProvider).joinRoom(code);
      if (mounted && room['matchId'] is String) {
        context.go('/match/${room['matchId']}');
      } else if (mounted) {
        setState(() => _error = 'กำลังเตรียมการแข่งขัน ลองอีกครั้ง');
      }
    } on DioException catch (error) {
      final body = error.response?.data;
      final code = body is Map ? body['code'] : null;
      final message = switch (code) {
        'room.not_found' => 'ไม่พบห้องนี้ หรือห้องหมดอายุแล้ว',
        'room.invalid_code' => 'รูปแบบรหัสห้องไม่ถูกต้อง',
        'room.full' => 'ห้องนี้มีผู้เล่นครบแล้ว',
        'room.already_in_room' => 'คุณอยู่ในห้องอื่นแล้ว',
        'room.not_waiting' => 'ห้องนี้ไม่รับผู้เล่นเพิ่มแล้ว',
        'room.match_starting' => 'กำลังเริ่มเกม ลองอีกครั้ง',
        'room.owner_cannot_join' => 'คุณเป็นเจ้าของห้องนี้อยู่แล้ว',
        'room.in_matchmaking_queue' => 'ออกจากคิวจับคู่ก่อนเข้าห้อง',
        'match.already_active' => 'คุณมีการแข่งขันที่ยังไม่จบ',
        _ => 'เข้าร่วมห้องไม่สำเร็จ ลองอีกครั้ง',
      };
      if (mounted) setState(() => _error = message);
    } catch (_) {
      if (mounted) setState(() => _error = 'เข้าร่วมห้องไม่สำเร็จ ลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
}

class _ChallengerArt extends StatelessWidget {
  const _ChallengerArt({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.xl),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0x4D5D9BD3), Color(0x000B1726)],
            radius: .9,
          ),
        ),
        child: Column(
          children: [
            Image.asset(
              'assets/images/units/fighter.png',
              height: compact ? 136 : 250,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.shield_outlined,
                size: 110,
                color: Color(0xFF8AD6FF),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ผู้ท้าชิงคนต่อไป คือคุณ',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFFFE7AC),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'รับรหัสจากเพื่อน แล้วเข้าสู่สนามเดียวกัน',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _JoinForm extends StatelessWidget {
  const _JoinForm({
    required this.controller,
    required this.error,
    required this.onCodeChanged,
    required this.onJoin,
    required this.joining,
    required this.online,
    required this.onCreateRoom,
  });

  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onJoin;
  final bool joining;
  final bool online;
  final VoidCallback onCreateRoom;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: const BoxDecoration(
          color: Color(0xF20B1C2C),
          border: Border(
            top: BorderSide(color: Color(0xFFF2C14E), width: 2),
            bottom: BorderSide(color: Color(0x33829EB2)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'มีรหัสห้องแล้ว?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('ใส่รหัสเชิญเพื่อเข้าร่วมกับเพื่อน'),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              onChanged: onCodeChanged,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (controller.text.trim().isNotEmpty && !joining) onJoin();
              },
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s]')),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                labelText: 'รหัสห้อง',
                hintText: 'ABC234',
                errorText: error,
                helperText:
                    error == null ? 'วางรหัสได้ ระบบจัดรูปแบบให้' : null,
                prefixIcon: const Icon(Icons.key_outlined),
                filled: true,
                fillColor: const Color(0xFF071321),
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: controller.text.trim().isEmpty || joining || !online
                  ? null
                  : onJoin,
              child: Text(joining ? 'กำลังเข้าร่วมห้อง…' : 'เข้าร่วมห้อง'),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: onCreateRoom,
              child: const Text('สร้างห้องของฉันแทน'),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!online)
              const Text(
                'ขาดการเชื่อมต่อเกม กำลังเชื่อมต่อใหม่…',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      );
}
