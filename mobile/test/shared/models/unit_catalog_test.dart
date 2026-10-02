import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:auto_chess_mobile/shared/models/unit_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unitCatalog', () {
    test('contains exactly 4 entries — one per UnitId', () {
      expect(unitCatalog.length, UnitId.values.length);
      for (final id in UnitId.values) {
        expect(unitCatalog.containsKey(id), isTrue, reason: '$id missing');
      }
    });

    test('every entry has the correct id key', () {
      for (final entry in unitCatalog.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('every entry has a non-empty name', () {
      for (final entry in unitCatalog.values) {
        expect(entry.name, isNotEmpty, reason: '${entry.id} name is empty');
      }
    });

    test('every entry has a non-empty role', () {
      for (final entry in unitCatalog.values) {
        expect(entry.role, isNotEmpty, reason: '${entry.id} role is empty');
      }
    });

    test('costs match known values (fighter=1, healer=1, ranger=2, tank=2)',
        () {
      expect(unitCatalog[UnitId.fighter]!.cost, 1);
      expect(unitCatalog[UnitId.healer]!.cost, 1);
      expect(unitCatalog[UnitId.ranger]!.cost, 2);
      expect(unitCatalog[UnitId.tank]!.cost, 2);
    });

    test('base stats mirror backend UNIT_BASE_STATS', () {
      expect(
        {
          for (final entry in unitCatalog.entries)
            entry.key: [entry.value.hp, entry.value.atk, entry.value.spd],
        },
        {
          UnitId.fighter: [100, 15, 20],
          UnitId.healer: [70, 6, 50],
          UnitId.ranger: [60, 12, 67],
          UnitId.tank: [150, 8, 0],
        },
      );
    });

    test('ATK uses the same floor ×1/×1.5/×2 scaling as the backend', () {
      expect(
        [
          for (final tier in [0, 1, 2])
            unitCatalog[UnitId.fighter]!.attackAtFusionTier(tier),
        ],
        [15, 22, 30],
      );
      expect(
        [
          for (final tier in [0, 1, 2])
            unitCatalog[UnitId.healer]!.attackAtFusionTier(tier),
        ],
        [6, 9, 12],
      );
      expect(
        [
          for (final tier in [0, 1, 2])
            unitCatalog[UnitId.ranger]!.attackAtFusionTier(tier),
        ],
        [12, 18, 24],
      );
      expect(
        [
          for (final tier in [0, 1, 2])
            unitCatalog[UnitId.tank]!.attackAtFusionTier(tier),
        ],
        [8, 12, 16],
      );
    });

    test('3-star healer documents both double heal and slow', () {
      final description = unitCatalog[UnitId.healer]!.abilities[2].description;
      expect(description, contains('สองตัว'));
      expect(description, contains('SPD'));
      expect(description, contains('70%'));
    });

    test('every entry has exactly 3 abilities (one per star form)', () {
      for (final entry in unitCatalog.values) {
        expect(
          entry.abilities.length,
          3,
          reason: '${entry.id} should have 3 abilities',
        );
      }
    });

    test('star levels are 1, 2, 3 in order', () {
      for (final entry in unitCatalog.values) {
        for (var i = 0; i < entry.abilities.length; i++) {
          expect(
            entry.abilities[i].starLevel,
            i + 1,
            reason: '${entry.id} ability[$i] star level',
          );
        }
      }
    });

    test('every ability has a non-empty description', () {
      for (final entry in unitCatalog.values) {
        for (final ability in entry.abilities) {
          expect(
            ability.description,
            isNotEmpty,
            reason: '${entry.id} ★${ability.starLevel} description is empty',
          );
        }
      }
    });
  });
}
