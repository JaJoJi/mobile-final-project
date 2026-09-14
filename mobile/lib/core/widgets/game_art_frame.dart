import 'package:flutter/material.dart';

/// Responsive arena backgrounds kept separate from interactive UI layers.
abstract final class GameBackgroundAssets {
  static const String arenaPortrait =
      'assets/images/backgrounds/arena_background_portrait.webp';
  static const String arenaLandscape =
      'assets/images/backgrounds/arena_background_landscape.webp';
  static const String arenaBlurred =
      'assets/images/backgrounds/arena_background_blurred.webp';

  static const List<String> all = [
    arenaPortrait,
    arenaLandscape,
    arenaBlurred,
  ];
}

/// Asset paths and nine-slice geometry for the fantasy match HUD.
abstract final class GameUiAssets {
  static const String panelTextureBlue =
      'assets/images/ui/panel_texture_blue.webp';
  static const String panelTextureStone =
      'assets/images/ui/panel_texture_stone.webp';
  static const String reservePanelFrame =
      'assets/images/ui/reserve_panel_frame.png';
  static const String reserveSlotFrame =
      'assets/images/ui/reserve_slot_frame.png';
  static const String shopPanelFrame = 'assets/images/ui/shop_panel_frame.png';
  static const String shopCardFrame = 'assets/images/ui/shop_card_frame.png';
  static const String hudPlayerFrame = 'assets/images/ui/hud_player_frame.png';
  static const String hudEnemyFrame = 'assets/images/ui/hud_enemy_frame.png';
  static const String hudTimerMedallion =
      'assets/images/ui/hud_timer_medallion.png';
  static const String hudHealthTrack = 'assets/images/ui/hud_health_track.png';
  static const String actionBarFrame = 'assets/images/ui/action_bar_frame.png';
  static const String readyButtonFrame =
      'assets/images/ui/ready_button_frame.png';
  static const String secondaryButtonFrame =
      'assets/images/ui/secondary_button_frame.png';
  static const String scoutPanelFrame =
      'assets/images/ui/scout_panel_frame.png';
  static const String resultPanelFrame =
      'assets/images/ui/result_panel_frame.png';

  static const List<String> all = [
    panelTextureBlue,
    panelTextureStone,
    reservePanelFrame,
    reserveSlotFrame,
    shopPanelFrame,
    shopCardFrame,
    ...hud,
  ];

  static const List<String> shop = [
    panelTextureBlue,
    shopPanelFrame,
    shopCardFrame,
  ];

  static const List<String> reserve = [
    panelTextureBlue,
    reservePanelFrame,
    reserveSlotFrame,
  ];

  static const List<String> hud = [
    hudPlayerFrame,
    hudEnemyFrame,
    hudTimerMedallion,
    hudHealthTrack,
    actionBarFrame,
    readyButtonFrame,
    secondaryButtonFrame,
    scoutPanelFrame,
    resultPanelFrame,
  ];
}

enum GameArtFrameKind { panel, card }

/// Paints a repeatable texture below [child] and a transparent nine-slice
/// frame above it. Text, icons and interaction states remain Flutter widgets.
class GameArtFrame extends StatelessWidget {
  const GameArtFrame({
    super.key,
    required this.frameAsset,
    required this.child,
    this.textureAsset = GameUiAssets.panelTextureBlue,
    this.kind = GameArtFrameKind.panel,
    this.padding = EdgeInsets.zero,
    this.centerSlice,
    this.assetScale = 4,
  });

  final String frameAsset;
  final String? textureAsset;
  final GameArtFrameKind kind;
  final EdgeInsetsGeometry padding;
  final Rect? centerSlice;
  final double assetScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isCard = kind == GameArtFrameKind.card;
    // Assets are supplied at 4x. Keeping corner rails at their native logical
    // size prevents distortion while the transparent centre stretches.
    final effectiveCenterSlice = centerSlice ??
        (isCard
            ? const Rect.fromLTWH(14, 14, 36, 68)
            : const Rect.fromLTWH(14, 14, 36, 36));

    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (textureAsset != null)
            Positioned.fill(
              child: Image.asset(
                textureAsset!,
                scale: assetScale,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                ),
              ),
            ),
          Padding(padding: padding, child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.scale(
                // Card artwork includes a small transparent export margin.
                // Overscan the decorative layer so its visible rails meet the
                // card background without changing content or hit-box size.
                scale: isCard ? 1.07 : 1,
                child: Image.asset(
                  frameAsset,
                  scale: assetScale,
                  centerSlice: effectiveCenterSlice,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
