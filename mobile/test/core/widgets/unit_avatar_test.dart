import 'package:auto_chess_mobile/core/widgets/unit_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widgets/_harness.dart';

void main() {
  testWidgets(
      'board avatar gives the illustration more headroom than the other '
      'edges — the source art has almost none of its own', (tester) async {
    // `assets/images/units/*.png` draw the character nearly edge-to-edge
    // (~4% margin top *and* bottom, measured directly from the PNGs).
    // The board/bench/replay variant's frame is a perfect square matching
    // the art's own canvas, so `BoxFit.contain` renders it at 1:1 with no
    // extra letterboxing to hide that — unlike the shop variant, whose
    // taller 64:96 frame pillarboxes the square art and gives headroom
    // "for free". Reported live as a unit's head reading as jammed
    // against the top of its tile, at every avatar size, because it's
    // the same ~4% margin everywhere, not a scaling artifact.
    await pumpThemed(
      tester,
      const UnitAvatar(
        unitId: 'fighter',
        star: 0,
      ),
    );

    final art = find.descendant(
      of: find.byType(UnitAvatar),
      matching: find.byType(Image),
    );
    expect(art, findsOneWidget);
    final wrapper = tester.widget<Padding>(
      find.ancestor(of: art, matching: find.byType(Padding)).first,
    );
    final insets = wrapper.padding.resolve(TextDirection.ltr);
    expect(
      insets.top,
      greaterThan(insets.left),
      reason: 'top inset ($insets) is no bigger than the sides — the '
          "art's own baked-in margin is the only headroom the head gets",
    );
    expect(
      insets.top,
      greaterThan(insets.bottom),
      reason: 'top inset ($insets) is no bigger than the bottom — a unit '
          'should read as standing on its tile, not centred in it',
    );
  });
}
