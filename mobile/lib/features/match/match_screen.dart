import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

/// In-game screen — real implementation lands in P0-FE-04.
class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        title: 'แมตช์ $matchId',
        owner: 'P0-FE-04 · In-game screen',
      );
}
