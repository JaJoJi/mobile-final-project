/// Unit catalog — the mobile mirror of the server's authoritative unit rules.
///
/// The catalog list, full detail screen, and in-match detail sheet all read
/// from [unitCatalog] so names, prices, stats, and abilities stay consistent.
/// Numeric values mirror `backend/src/game/constants.ts` and
/// `backend/src/shop/shop.service.ts`; ability text mirrors the behavior in
/// `backend/src/game/abilities.ts`, `targeting.ts`, and `damage.ts`.
library;

import '../models/unit.dart';

/// One star-level ability entry.
class UnitAbility {
  const UnitAbility({required this.starLevel, required this.description});

  /// Display star level (1, 2, or 3).
  final int starLevel;

  /// Thai description of the ability at this star level.
  final String description;
}

/// Everything the UI needs to present a single unit archetype.
class UnitCatalogEntry {
  const UnitCatalogEntry({
    required this.id,
    required this.name,
    required this.role,
    required this.hp,
    required this.atk,
    required this.spd,
    required this.cost,
    required this.abilities,
  });

  /// The enum key shared with the server.
  final UnitId id;

  /// Thai display name — 'นักรบ', 'นักบวช', 'พลธนู', 'อัศวินโล่'.
  final String name;

  /// Short Thai role description.
  final String role;

  /// Base HP (Health Points).
  final int hp;

  /// Base ATK (Attack).
  final int atk;

  /// Base SPD (Speed).
  final int spd;

  /// Gold cost to buy this unit in the shop.
  final int cost;

  /// Abilities indexed by display star level (1, 2, 3).
  final List<UnitAbility> abilities;

  /// The server scales ATK by ×1, ×1.5, and ×2 for fusion tiers 0, 1, and 2.
  /// Dart integer division preserves the server's `Math.floor` behavior.
  int attackAtFusionTier(int fusionTier) => switch (fusionTier) {
        0 => atk,
        1 => atk * 3 ~/ 2,
        2 => atk * 2,
        _ => throw RangeError.range(fusionTier, 0, 2, 'fusionTier'),
      };
}

/// The canonical catalog. Every screen that needs unit display data reads
/// from this map — no duplicating strings or numbers elsewhere.
const Map<UnitId, UnitCatalogEntry> unitCatalog = {
  UnitId.fighter: UnitCatalogEntry(
    id: UnitId.fighter,
    name: 'นักรบ',
    role: 'สมดุลและดูดเลือด',
    hp: 100,
    atk: 15,
    spd: 20,
    cost: 1,
    abilities: [
      UnitAbility(
        starLevel: 1,
        description: 'ยังไม่มีความสามารถพิเศษ',
      ),
      UnitAbility(
        starLevel: 2,
        description: 'ดูดเลือด 5% หลังโจมตีสำเร็จ',
      ),
      UnitAbility(
        starLevel: 3,
        description: 'ดูดเลือด 10% หลังโจมตีสำเร็จ',
      ),
    ],
  ),
  UnitId.healer: UnitCatalogEntry(
    id: UnitId.healer,
    name: 'นักบวช',
    role: 'สนับสนุนและฟื้นฟู',
    hp: 70,
    atk: 6,
    spd: 50,
    cost: 1,
    abilities: [
      UnitAbility(
        starLevel: 1,
        description:
            'ฮีลยูนิตฝ่ายเราที่ HP ต่ำสุด 10 หน่วยทุกครั้งที่ออกแอ็กชัน',
      ),
      UnitAbility(
        starLevel: 2,
        description:
            'ฮีลยูนิตฝ่ายเราที่ HP ต่ำสุด 10 หน่วย และลด SPD ของศัตรูที่โจมตีเหลือ 70% จนกว่าจะออกแอ็กชันครั้งถัดไป',
      ),
      UnitAbility(
        starLevel: 3,
        description:
            'ฮีลยูนิตฝ่ายเราที่ HP ต่ำสุดสองตัว ตัวละ 10 หน่วย และลด SPD ของศัตรูที่โจมตีเหลือ 70% จนกว่าจะออกแอ็กชันครั้งถัดไป',
      ),
    ],
  ),
  UnitId.ranger: UnitCatalogEntry(
    id: UnitId.ranger,
    name: 'พลธนู',
    role: 'สร้างความเสียหายระยะไกล',
    hp: 60,
    atk: 12,
    spd: 67,
    cost: 2,
    abilities: [
      UnitAbility(
        starLevel: 1,
        description: 'ยังไม่มีความสามารถพิเศษ',
      ),
      UnitAbility(
        starLevel: 2,
        description:
            'สร้างความเสียหายทะลุ 10% แก่ศัตรูที่อยู่ด้านหลังเป้าหมายติดกันในช่องแนวเดียวกัน',
      ),
      UnitAbility(
        starLevel: 3,
        description: 'เล็งศัตรูที่มี HP ต่ำสุดจากทุกช่องในสนาม',
      ),
    ],
  ),
  UnitId.tank: UnitCatalogEntry(
    id: UnitId.tank,
    name: 'อัศวินโล่',
    role: 'แนวหน้าและรับความเสียหาย',
    hp: 150,
    atk: 8,
    spd: 0,
    cost: 2,
    abilities: [
      UnitAbility(
        starLevel: 1,
        description: 'ยังไม่มีความสามารถพิเศษ',
      ),
      UnitAbility(
        starLevel: 2,
        description: 'ฟื้นคืนชีพด้วย HP 50% ได้หนึ่งครั้งต่อการต่อสู้',
      ),
      UnitAbility(
        starLevel: 3,
        description:
            'บังคับนักรบ อัศวินโล่ และนักบวชฝ่ายตรงข้ามให้เล็งตนก่อน พร้อมฟื้นคืนชีพด้วย HP 50% ได้หนึ่งครั้งต่อการต่อสู้',
      ),
    ],
  ),
};
