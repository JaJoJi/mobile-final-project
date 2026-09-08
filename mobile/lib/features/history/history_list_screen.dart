import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

/// Past-matches list — real implementation lands in P1-FE-01.
class HistoryListScreen extends StatelessWidget {
  const HistoryListScreen({super.key});

  static const path = '/history';

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'ประวัติแมตช์',
        owner: 'P1-FE-01 · Past-matches list',
      );
}
