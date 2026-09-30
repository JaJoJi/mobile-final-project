import 'package:auto_chess_mobile/shared/models/unit.dart';
import 'package:auto_chess_mobile/shared/models/unit_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog has the four backend units with matching base stats and cost',
      () {
    expect(UnitCatalogEntry.entries.map((e) => e.id), UnitId.values);
    expect(
      UnitCatalogEntry.entries.map((e) => [e.cost, e.hp, e.atk, e.spd]),
      [
        [1, 100, 15, 20],
        [1, 70, 6, 50],
        [2, 60, 12, 67],
        [2, 150, 8, 0],
      ],
    );
  });

  test('all units describe each tier and use backend ATK scaling', () {
    for (final entry in UnitCatalogEntry.entries) {
      expect(entry.atkForTier(0), entry.atk);
      expect(entry.atkForTier(1), (entry.atk * 1.5).floor());
      expect(entry.atkForTier(2), entry.atk * 2);
      for (var tier = 0; tier <= 2; tier++) {
        expect(entry.abilityForTier(tier), isNotEmpty);
      }
    }
    expect(
      UnitCatalogEntry.of(UnitId.ranger).abilityForTier(2),
      isNot(contains('ทะลุ')),
    );
  });
}
