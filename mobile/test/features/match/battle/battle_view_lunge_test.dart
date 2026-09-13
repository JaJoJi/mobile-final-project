import 'package:auto_chess_mobile/features/match/battle/battle_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lungeOffsetFor', () {
    test('reaches across the board gap toward the enemy board at progress 1.0',
        () {
      final offset = lungeOffsetFor(
        lungeDx: 1,
        lungeDy: -1,
        tileWidth: 80,
        boardHeight: 260,
        progress: 1.0,
      );

      expect(offset, const Offset(96, -260));
    });

    test('stays at the origin tile at progress 0.0', () {
      final offset = lungeOffsetFor(
        lungeDx: 1,
        lungeDy: -1,
        tileWidth: 80,
        boardHeight: 260,
        progress: 0.0,
      );

      expect(offset, Offset.zero);
    });

    test('scales linearly with progress for a diagonal direction', () {
      final offset = lungeOffsetFor(
        lungeDx: -1,
        lungeDy: 1,
        tileWidth: 100,
        boardHeight: 240,
        progress: 0.5,
      );

      expect(offset, const Offset(-60, 120));
    });

    test(
        'matches the ranged projectile\'s travel formula for the same '
        'direction/tile inputs', () {
      // battle_view.dart's projectile travel: dx = lungeDx * tileWidth * 1.2,
      // dy = isAlly ? -boardHeight : boardHeight. Melee lunge should read as
      // the same "cross to the enemy board" motion, just there-and-back.
      const tileWidth = 90.0;
      const boardHeight = 270.0;
      const projectileTravelX = 1 * tileWidth * 1.2;
      const projectileTravelY = -boardHeight; // ally side

      final lunge = lungeOffsetFor(
        lungeDx: 1,
        lungeDy: -1,
        tileWidth: tileWidth,
        boardHeight: boardHeight,
        progress: 1.0,
      );

      expect(lunge.dx, projectileTravelX);
      expect(lunge.dy, projectileTravelY);
    });
  });
}
