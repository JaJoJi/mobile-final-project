import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'state_views.dart';

/// The common screen frame — design spec §4 common frame + §16.1.
///
/// `Scaffold` → sticky [ConnectionBanner] → `SafeArea` → `lg` padding.
/// Every screen uses this so the connection status and the safe-area /
/// padding rules are applied in exactly one place.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.connectionStatus = ConnectionStatus.connected,
    this.onReconnect,
    this.reconnectInSeconds,
    this.floatingActionButton,
    this.bottomBar,
    this.padded = true,
    this.scrollable = false,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final ConnectionStatus connectionStatus;
  final VoidCallback? onReconnect;
  final int? reconnectInSeconds;
  final Widget? floatingActionButton;
  final Widget? bottomBar;

  /// Apply the default `lg` screen padding. Turn off for full-bleed screens
  /// (e.g. the match board) that pad their own sections.
  final bool padded;

  /// Wrap [body] in a `SingleChildScrollView` (forms **[MUST]**).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    Widget content = body;
    if (padded) {
      content = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: content,
      );
    }
    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }

    return Scaffold(
      appBar:
          title != null ? AppBar(title: Text(title!), actions: actions) : null,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
      body: Column(
        children: [
          ConnectionBanner(
            status: connectionStatus,
            onRetry: onReconnect,
            retryInSeconds: reconnectInSeconds,
          ),
          Expanded(
            child: SafeArea(
              top: title == null,
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
