import 'package:flutter/material.dart';

/// Reusable player identity crest for Player Hub screens.
class PlayerCrest extends StatelessWidget {
  const PlayerCrest({
    super.key,
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 76.0 : 108.0;
    final height = compact ? 92.0 : 130.0;
    return Container(
      key: const ValueKey('player-crest'),
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEAB0), Color(0xFF8D7546), Color(0xFFF2C14E)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(54),
          bottomRight: Radius.circular(54),
        ),
        border: Border.all(color: const Color(0xFFFFF2C9), width: 2),
      ),
      child: Container(
        width: width - 14,
        height: height - 14,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFF102B42),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(13),
            topRight: Radius.circular(13),
            bottomLeft: Radius.circular(48),
            bottomRight: Radius.circular(48),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFFFFD35A),
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
