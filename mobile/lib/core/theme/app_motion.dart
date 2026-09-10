import 'package:flutter/animation.dart';

/// Motion tokens — design spec §2.4. Material 3 easing + duration scale.
///
/// Rule: **enter = decelerate and longer, exit = accelerate and shorter.**
/// **[MUST]** Anything longer than 400 ms must be skippable, and all
/// decorative motion is dropped when
/// `MediaQuery.disableAnimationsOf(context)` is true.
abstract final class AppMotion {
  /// 100 ms — ripple, colour change, press state.
  static const Duration short2 = Duration(milliseconds: 100);

  /// 200 ms — icon toggle, HP-bar tween, card scale 1.0→1.05.
  static const Duration short4 = Duration(milliseconds: 200);

  /// 300 ms — page transition, toast in/out, snap-to-slot.
  static const Duration medium2 = Duration(milliseconds: 300);

  /// 400 ms — modal in, card expand.
  static const Duration medium4 = Duration(milliseconds: 400);

  /// 500 ms — phase change (shop → battle).
  static const Duration long2 = Duration(milliseconds: 500);

  /// 800 ms — match-end cinematic.
  static const Duration extraLong2 = Duration(milliseconds: 800);

  /// 1500 ms — enough time to read the end-of-round result; tap skips it.
  static const Duration roundResult = Duration(milliseconds: 1500);

  /// Default for anything the player notices.
  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Element entering the screen.
  static const Cubic emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Element leaving the screen.
  static const Cubic emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Small changes that should feel immediate.
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Returns [d] or [Duration.zero] when the platform asks for reduced motion.
  static Duration maybe(Duration d, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : d;
}
