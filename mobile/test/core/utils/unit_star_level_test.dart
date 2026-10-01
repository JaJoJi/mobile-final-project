import 'package:auto_chess_mobile/core/utils/unit_star_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the server fusion tiers to player-facing star levels', () {
    expect(displayStarLevel(0), 1);
    expect(displayStarLevel(1), 2);
    expect(displayStarLevel(2), 3);
  });
}
