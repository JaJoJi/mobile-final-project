/// Roster unit — one entry in a player's board (9 slots) or bench (8 slots).
///
/// Mirrors the backend `RuntimeUnitState` as it appears inside
/// `game:match:state` (`docs/04-api-contracts.md` §2 — `game:match:state`).
///
/// Board slot indexing is row-major: `col = slot % 3`, `row = slot ~/ 3`,
/// with row 0 = front, row 1 = middle, row 2 = back.
library;

/// The four unit archetypes the server can offer / place.
enum UnitId {
  fighter,
  healer,
  ranger,
  tank;

  static UnitId fromJson(String? raw) => switch (raw) {
        'fighter' => UnitId.fighter,
        'healer' => UnitId.healer,
        'ranger' => UnitId.ranger,
        'tank' => UnitId.tank,
        _ => UnitId.fighter,
      };

  String toJson() => name;
}

/// A `{ row, col }` position on the 3×3 board, derived from a board slot.
class BoardPosition {
  const BoardPosition({required this.row, required this.col});

  /// 0 = front, 1 = middle, 2 = back.
  final int row;

  /// 0..2, left to right.
  final int col;

  /// Row-major slot index this position maps to (0..8).
  int get slot => row * 3 + col;

  /// Build a position from a row-major board slot (0..8).
  factory BoardPosition.fromSlot(int slot) =>
      BoardPosition(row: slot ~/ 3, col: slot % 3);

  @override
  bool operator ==(Object other) =>
      other is BoardPosition && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'BoardPosition(row: $row, col: $col)';
}

class Unit {
  const Unit({
    required this.instanceId,
    required this.unitId,
    required this.star,
    required this.hp,
    required this.maxHp,
  });

  /// Stable per-match id for this unit instance (used by every shop/place
  /// action and by the combat-event stream to address the unit).
  final String instanceId;
  final UnitId unitId;

  /// 0, 1, or 2 — the fusion tier.
  final int star;
  final int hp;
  final int maxHp;

  double get hpFraction => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);

  bool get isAlive => hp > 0;

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        instanceId: j['instanceId'] as String? ?? '',
        unitId: UnitId.fromJson(j['unitId'] as String?),
        star: (j['star'] as num?)?.toInt() ?? 0,
        hp: (j['hp'] as num?)?.toInt() ?? 0,
        maxHp: (j['maxHp'] as num?)?.toInt() ?? 0,
      );

  /// Parse a fixed-length slot list (`board` = 9, `bench` = 8) where each
  /// entry is either a unit map or `null` for an empty slot.
  static List<Unit?> slotsFromJson(Object? raw, int length) {
    final list = raw is List ? raw : const <Object?>[];
    return List<Unit?>.generate(
      length,
      (i) {
        if (i >= list.length) return null;
        final entry = list[i];
        return entry is Map<String, dynamic> ? Unit.fromJson(entry) : null;
      },
      growable: false,
    );
  }

  @override
  String toString() => 'Unit($unitId ★$star $hp/$maxHp id=$instanceId)';
}
