import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../lobby/player_hub_navigation.dart';
import '../player_hub/player_hub_shell.dart';
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
    final online = ref.watch(wsConnectionStateProvider).valueOrNull ==
        WsConnectionState.connected;
    return PlayerHubShell(
      title: 'เข้าร่วมห้อง',
      badge: '1 VS 1',
      lighter: true,
      headerLeading: IconButton(
        tooltip: 'ย้อนกลับ',
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/lobby'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      navigation: const PlayerHubNavigation(selected: PlayerHubTab.home),
      body: _buildJoinForm(context, online),
    );
  }

  Widget _buildJoinForm(BuildContext context, bool online) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          return SingleChildScrollView(
            padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
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
      await ref.read(apiClientProvider).joinRoom(code);
      if (mounted) context.go(CreateRoomScreen.path);
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
  Widget build(BuildContext context) => FantasyPanel(
        translucent: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0x332BD9FF), Color(0x33F2C14E)],
                  ),
                  borderRadius: AppRadius.allFull,
                  border: Border.all(color: const Color(0x80F2C14E)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sports_martial_arts_rounded,
                      size: AppSpacing.lg,
                      color: Color(0xFFFFD35A),
                    ),
                    SizedBox(width: AppSpacing.xs),
                    Text('การดวลส่วนตัว'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
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
                        'กรอกรหัสห้อง',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFFFFF1C4),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'ใช้รหัส 6 ตัวที่ได้รับจากเพื่อน',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFB8CEF0),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _RoomCodeField(
              controller: controller,
              onChanged: onCodeChanged,
              error: error,
              onSubmitted: () {
                if (controller.text.trim().isNotEmpty && !joining) onJoin();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ถึงเวลาพิสูจน์ฝีมือ!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFFFE49A),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: controller.text.trim().isEmpty || joining || !online
                  ? null
                  : onJoin,
              icon: const Icon(Icons.login_rounded),
              label: Text(joining ? 'กำลังเข้าร่วมห้อง…' : 'เข้าร่วมห้อง'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'หรือ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onCreateRoom,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('สร้างห้อง'),
            ),
          ],
        ),
      );
}

class _RoomCodeField extends StatelessWidget {
  const _RoomCodeField({
    required this.controller,
    required this.onChanged,
    required this.error,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    const placeholder = 'ABC234';
    final normalized =
        controller.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          textField: true,
          label: 'รหัสห้อง 6 ตัว',
          child: SizedBox(
            height: 72,
            child: Stack(
              children: [
                Row(
                  children: List.generate(6, (index) {
                    final hasValue = index < normalized.length;
                    final character =
                        hasValue ? normalized[index] : placeholder[index];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: index == 5 ? 0 : AppSpacing.xs,
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: hasValue
                                  ? const [
                                      Color(0xFF173A55),
                                      Color(0xFF081827),
                                    ]
                                  : const [
                                      Color(0xFF102538),
                                      Color(0xFF071321),
                                    ],
                            ),
                            borderRadius: AppRadius.allSm,
                            border: Border.all(
                              color: hasValue
                                  ? const Color(0xFF8AD6FF)
                                  : const Color(0x806FA5C4),
                            ),
                            boxShadow: hasValue
                                ? const [
                                    BoxShadow(
                                      color: Color(0x4059B7E8),
                                      blurRadius: AppSpacing.sm,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            character,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: hasValue
                                      ? const Color(0xFFF4F7FF)
                                      : const Color(0x4DF4F7FF),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: .01,
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      onSubmitted: (_) => onSubmitted(),
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9\s]'),
                        ),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(color: Colors.transparent),
                      cursorColor: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          error ?? 'ตัวอักษร A-Z หรือตัวเลข 2-9',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: error == null
                    ? const Color(0xFF91A2B8)
                    : Theme.of(context).colorScheme.error,
              ),
        ),
      ],
    );
  }
}
