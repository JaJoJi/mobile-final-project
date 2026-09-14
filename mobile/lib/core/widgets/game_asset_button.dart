import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'game_art_frame.dart';

/// A responsive game-styled button. Its label and state remain live Flutter
/// content while the generated artwork is used only as a stretchable skin.
class GameAssetButton extends StatefulWidget {
  const GameAssetButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.frameAsset = GameUiAssets.secondaryButtonFrame,
    this.selected = false,
    this.disabledReason,
    this.accentColor,
    this.minHeight = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    this.stretchFrame = true,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final String frameAsset;
  final bool selected;
  final String? disabledReason;
  final Color? accentColor;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final bool stretchFrame;

  @override
  State<GameAssetButton> createState() => _GameAssetButtonState();
}

class _GameAssetButtonState extends State<GameAssetButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final button = Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      child: AnimatedOpacity(
        opacity: _enabled ? 1 : 0.46,
        duration: AppMotion.maybe(
          AppMotion.short2,
          reduceMotion: reduceMotion,
        ),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: AppMotion.maybe(
            AppMotion.short2,
            reduceMotion: reduceMotion,
          ),
          child: AnimatedContainer(
            duration: AppMotion.maybe(
              AppMotion.short4,
              reduceMotion: reduceMotion,
            ),
            constraints:
                BoxConstraints(minWidth: 48, minHeight: widget.minHeight),
            decoration: BoxDecoration(
              borderRadius: AppRadius.allMd,
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.72),
                        blurRadius: AppSpacing.md,
                        spreadRadius: AppSpacing.xxs,
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                onHighlightChanged: _enabled
                    ? (pressed) => setState(() => _pressed = pressed)
                    : null,
                borderRadius: AppRadius.allMd,
                child: Stack(
                  fit: StackFit.passthrough,
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Image.asset(
                          widget.frameAsset,
                          scale: 4,
                          centerSlice: widget.stretchFrame
                              ? const Rect.fromLTWH(42, 18, 108, 24)
                              : null,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Padding(padding: widget.padding, child: widget.child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!_enabled && widget.disabledReason != null) {
      return Tooltip(message: widget.disabledReason!, child: button);
    }
    return button;
  }
}
