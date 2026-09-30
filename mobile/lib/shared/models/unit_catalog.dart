import 'unit.dart';

/// Static unit data mirrored from backend/src/game/constants.ts and
/// backend/src/shop/shop.service.ts. Match HP is kept on [Unit] instead.
class UnitCatalogEntry {
  const UnitCatalogEntry({
    required this.id,
    required this.name,
    required this.role,
    required this.summary,
    required this.cost,
    required this.hp,
    required this.atk,
    required this.spd,
  });

  final UnitId id;
  final String name;
  final String role;
  final String summary;
  final int cost;
  final int hp;
  final int atk;
  final int spd;

  int atkForTier(int tier) {
    assert(tier >= 0 && tier <= 2);
    return switch (tier) {
      1 => (atk * 1.5).floor(),
      2 => atk * 2,
      _ => atk,
    };
  }

  String abilityForTier(int tier) {
    assert(tier >= 0 && tier <= 2);
    return switch (id) {
      UnitId.fighter => switch (tier) {
          1 => 'ดูดเลือด 5% ของความเสียหายหลังโจมตีสำเร็จ',
          2 => 'ดูดเลือด 10% ของความเสียหายหลังโจมตีสำเร็จ',
          _ => 'ยังไม่มีความสามารถพิเศษ',
        },
      UnitId.healer => switch (tier) {
          1 => 'ฮีลเพื่อนที่ HP ต่ำสุด 10 และทำให้เป้าหมายช้าลง',
          2 => 'ฮีลเพื่อน HP ต่ำสุดสองตัว ตัวละ 10 และทำให้เป้าหมายช้าลง',
          _ => 'ฮีลเพื่อนที่ HP ต่ำสุด 10 หลังโจมตี',
        },
      UnitId.ranger => switch (tier) {
          1 => 'ความเสียหาย 10% ทะลุไปยังศัตรูด้านหลัง',
          2 => 'เล็งศัตรู HP ต่ำสุดได้จากทุกช่อง',
          _ => 'ยังไม่มีความสามารถพิเศษ',
        },
      UnitId.tank => switch (tier) {
          1 => 'ฟื้นคืนชีพด้วย HP 50% ได้หนึ่งครั้งต่อรอบ',
          2 => 'บังคับศัตรูให้เล็งตน และยังฟื้นคืนชีพได้',
          _ => 'ยังไม่มีความสามารถพิเศษ',
        },
    };
  }

  static const entries = <UnitCatalogEntry>[
    UnitCatalogEntry(
      id: UnitId.fighter,
      name: 'นักรบ',
      role: 'ไฟต์เตอร์',
      summary: 'สมดุลทั้งพลังชีวิตและการโจมตี',
      cost: 1,
      hp: 100,
      atk: 15,
      spd: 20,
    ),
    UnitCatalogEntry(
      id: UnitId.healer,
      name: 'นักบวช',
      role: 'ซัพพอร์ต',
      summary: 'ฟื้นฟูเพื่อนร่วมทีมและลดความเร็วศัตรู',
      cost: 1,
      hp: 70,
      atk: 6,
      spd: 50,
    ),
    UnitCatalogEntry(
      id: UnitId.ranger,
      name: 'พลธนู',
      role: 'โจมตีระยะไกล',
      summary: 'โจมตีเป้าหมายที่อ่อนแอจากระยะไกล',
      cost: 2,
      hp: 60,
      atk: 12,
      spd: 67,
    ),
    UnitCatalogEntry(
      id: UnitId.tank,
      name: 'อัศวินโล่',
      role: 'แทงก์',
      summary: 'ยืนแนวหน้าและรับความเสียหายแทนทีม',
      cost: 2,
      hp: 150,
      atk: 8,
      spd: 0,
    ),
  ];

  static UnitCatalogEntry of(UnitId id) =>
      entries.firstWhere((e) => e.id == id);
}
