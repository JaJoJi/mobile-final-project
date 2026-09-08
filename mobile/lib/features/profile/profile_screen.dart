import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

/// Account + settings — real implementation lands in P1-FE-02.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const path = '/profile';

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
        title: 'บัญชีของฉัน',
        owner: 'P1-FE-02 · My-account screen',
      );
}
