import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Temporary scaffold for routes whose real screen is owned by a later
/// ticket. Keeps `buildRouter()`'s 7 routes wired and navigable so
/// P0-FE-02 can be verified end to end; each owner deletes this and drops
/// in the real screen.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.owner,
  });

  final String title;

  /// The ticket that will build the real screen (shown for the team).
  final String owner;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: context.canPop() ? BackButton(onPressed: context.pop) : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 48, color: t.colorScheme.outline),
              const SizedBox(height: 16),
              Text('กำลังพัฒนา', style: t.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(owner, style: t.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
