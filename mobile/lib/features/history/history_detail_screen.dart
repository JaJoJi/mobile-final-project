import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

/// Single-match detail — real implementation lands in P1-FE-01.
class MatchDetailScreen extends StatelessWidget {
  const MatchDetailScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        title: 'แมตช์ $matchId',
        owner: 'P1-FE-01 · Match detail',
      );
}
