import 'package:flutter/material.dart';

/// Game-only semantic colours — design spec §2.1.
///
/// These have no Material 3 role, so they live here as a [ThemeExtension]
/// rather than loose constants. Read them with
/// `Theme.of(context).extension<GameTheme>()!`.
///
/// **[MUST]** Team / HP / win-loss / damage-sign are never communicated by
/// colour alone — pair every use with an icon, label or position.
@immutable
class GameTheme extends ThemeExtension<GameTheme> {
  const GameTheme({
    required this.success,
    required this.warning,
    required this.ally,
    required this.enemy,
    required this.hpHigh,
    required this.hpMid,
    required this.hpLow,
    required this.gold,
    required this.star1,
    required this.star2,
    required this.boardCellEmpty,
    required this.boardCellValidDrop,
  });

  /// Win — result screen, history win rows.
  final Color success;

  /// Reconnecting banner, timer < 10 s.
  final Color warning;

  /// My units, my HP bar.
  final Color ally;

  /// Opponent units, opponent HP bar.
  final Color enemy;

  /// HP > 50 %.
  final Color hpHigh;

  /// HP 20–50 %.
  final Color hpMid;

  /// HP < 20 %.
  final Color hpLow;

  /// Gold counter, unit price.
  final Color gold;

  /// 1★ frame + star glyphs.
  final Color star1;

  /// 2★ frame + gold glow.
  final Color star2;

  /// Empty board slot fill.
  final Color boardCellEmpty;

  /// Drop-target highlight.
  final Color boardCellValidDrop;

  static const GameTheme _light = GameTheme(
    success: Color(0xFF256C2E),
    warning: Color(0xFF8A5000),
    ally: Color(0xFF3F51B5),
    enemy: Color(0xFFB3541E),
    hpHigh: Color(0xFF256C2E),
    hpMid: Color(0xFF8A5000),
    hpLow: Color(0xFFBA1A1A),
    gold: Color(0xFF7A5A00),
    star1: Color(0xFF5B6BC7),
    star2: Color(0xFFB58A00),
    boardCellEmpty: Color(0xFFE7E4EC),
    boardCellValidDrop: Color(0xFFC7D0FF),
  );

  static const GameTheme _dark = GameTheme(
    success: Color(0xFF8BD98F),
    warning: Color(0xFFFFB95C),
    ally: Color(0xFFB9C3FF),
    enemy: Color(0xFFFFB68C),
    hpHigh: Color(0xFF8BD98F),
    hpMid: Color(0xFFFFB95C),
    hpLow: Color(0xFFFFB4AB),
    gold: Color(0xFFF5C542),
    star1: Color(0xFFB9C3FF),
    star2: Color(0xFFF5C542),
    boardCellEmpty: Color(0xFF26252C),
    boardCellValidDrop: Color(0xFF3A4370),
  );

  static GameTheme of(Brightness brightness) =>
      brightness == Brightness.light ? _light : _dark;

  /// Star colour for a given star level (0 → 1★ tone, so a badge is still visible).
  Color starColor(int star) => star >= 2 ? star2 : star1;

  @override
  GameTheme copyWith({
    Color? success,
    Color? warning,
    Color? ally,
    Color? enemy,
    Color? hpHigh,
    Color? hpMid,
    Color? hpLow,
    Color? gold,
    Color? star1,
    Color? star2,
    Color? boardCellEmpty,
    Color? boardCellValidDrop,
  }) {
    return GameTheme(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      ally: ally ?? this.ally,
      enemy: enemy ?? this.enemy,
      hpHigh: hpHigh ?? this.hpHigh,
      hpMid: hpMid ?? this.hpMid,
      hpLow: hpLow ?? this.hpLow,
      gold: gold ?? this.gold,
      star1: star1 ?? this.star1,
      star2: star2 ?? this.star2,
      boardCellEmpty: boardCellEmpty ?? this.boardCellEmpty,
      boardCellValidDrop: boardCellValidDrop ?? this.boardCellValidDrop,
    );
  }

  @override
  GameTheme lerp(ThemeExtension<GameTheme>? other, double t) {
    if (other is! GameTheme) return this;
    return GameTheme(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      ally: Color.lerp(ally, other.ally, t)!,
      enemy: Color.lerp(enemy, other.enemy, t)!,
      hpHigh: Color.lerp(hpHigh, other.hpHigh, t)!,
      hpMid: Color.lerp(hpMid, other.hpMid, t)!,
      hpLow: Color.lerp(hpLow, other.hpLow, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      star1: Color.lerp(star1, other.star1, t)!,
      star2: Color.lerp(star2, other.star2, t)!,
      boardCellEmpty: Color.lerp(boardCellEmpty, other.boardCellEmpty, t)!,
      boardCellValidDrop:
          Color.lerp(boardCellValidDrop, other.boardCellValidDrop, t)!,
    );
  }
}
