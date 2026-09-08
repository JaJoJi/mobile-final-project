import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_button.dart';

/// Loading / empty / error / connection views — design spec §3.10.
///
/// Every network-backed screen maps its state onto exactly these, so the
/// app has one shape for each situation.

/// A single shimmering placeholder block. Mirror the real content's shape
/// (**[MUST]**), don't drop a generic spinner in.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    // Shimmer is decorative — hold it still under reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _box(base);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.55 + 0.35 * _c.value,
        child: _box(base),
      ),
    );
  }

  Widget _box(Color color) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// A column of [SkeletonBox] rows for list-shaped content.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6, this.rowHeight = 56});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) =>
          SkeletonBox(height: rowHeight, radius: AppRadius.md),
    );
  }
}

/// Icon + one sentence + one action. **[MUST]** all three.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _CenteredScrollColumn(
      children: [
        Icon(icon, size: 48, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.lg),
        Text(message,
            textAlign: TextAlign.center, style: t.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          onPressed: onAction,
          variant: AppButtonVariant.secondary,
          fullWidth: false,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

/// A vertically-centred column that scrolls instead of overflowing when the
/// parent is short (small screen, textScale 2.0).
class _CenteredScrollColumn extends StatelessWidget {
  const _CenteredScrollColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon + human message + a retry button. **[MUST]** always an exit.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _CenteredScrollColumn(
      children: [
        Icon(Icons.cloud_off_outlined, size: 48, color: t.colorScheme.error),
        const SizedBox(height: AppSpacing.lg),
        Text(message,
            textAlign: TextAlign.center, style: t.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          onPressed: onRetry,
          fullWidth: false,
          child: const Text('ลองอีกครั้ง'),
        ),
      ],
    );
  }
}

/// Realtime connection status.
enum ConnectionStatus { connected, connecting, reconnecting, disconnected }

/// Sticky top banner for the WebSocket connection — design spec §3.10 / §5.5.
///
/// Hidden entirely while [status] is [ConnectionStatus.connected]. On
/// [ConnectionStatus.disconnected] it offers a retry and (optionally) a
/// countdown to the automatic attempt.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
    this.onRetry,
    this.retryInSeconds,
  });

  final ConnectionStatus status;
  final VoidCallback? onRetry;
  final int? retryInSeconds;

  @override
  Widget build(BuildContext context) {
    if (status == ConnectionStatus.connected) return const SizedBox.shrink();

    final t = Theme.of(context);
    final danger = status == ConnectionStatus.disconnected;
    final bg = danger
        ? t.colorScheme.errorContainer
        : t.colorScheme.secondaryContainer;
    final fg = danger
        ? t.colorScheme.onErrorContainer
        : t.colorScheme.onSecondaryContainer;

    final label = switch (status) {
      ConnectionStatus.connecting => 'กำลังเชื่อมต่อ…',
      ConnectionStatus.reconnecting => 'กำลังเชื่อมต่อใหม่…',
      ConnectionStatus.disconnected => retryInSeconds != null
          ? 'การเชื่อมต่อหลุด ลองใหม่ใน $retryInSeconds วินาที'
          : 'การเชื่อมต่อหลุด',
      ConnectionStatus.connected => '',
    };

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                danger ? Icons.wifi_off : Icons.wifi_tethering,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: t.textTheme.bodyMedium?.copyWith(color: fg),
                ),
              ),
              if (danger && onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('เชื่อมต่อใหม่'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading-indicator choice helper — design spec §3.10.
/// `< 300 ms` show nothing · `300 ms–1 s` spinner · `> 1 s` / known shape → skeleton.
Widget loadingIndicatorFor(Duration elapsed, {Widget? skeleton}) {
  if (elapsed < const Duration(milliseconds: 300)) {
    return const SizedBox.shrink();
  }
  if (skeleton != null && elapsed > const Duration(seconds: 1)) {
    return skeleton;
  }
  return const Center(child: CircularProgressIndicator());
}
