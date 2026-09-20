import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/widgets.dart';
import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';
import 'history_providers.dart';
import 'match_list_item.dart';
import 'match_models.dart';

/// `/history` — the caller's past matches in the Player Hub visual language.
class HistoryListScreen extends ConsumerStatefulWidget {
  const HistoryListScreen({super.key});

  static const path = '/history';

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

enum _Filter { all, wins, losses }

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(matchHistoryProvider);

    return Theme(
      data: fantasySurfaceTheme(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FantasyBackdrop(
          lighter: true,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const PlayerHubHeader(),
                const _HistoryHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: _HistoryFilterBar(
                    selected: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                ),
                Expanded(
                  child: _HistoryBody(history: history, filter: _filter),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.history),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: AppSpacing.xl,
              color: Color(0xFFFFD35A),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ประวัติการแข่งขัน',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFFFF5D6),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                  ),
                  Text(
                    'ดูผลการแข่งขันล่าสุดของคุณ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD7E8FF),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final _Filter selected;
  final ValueChanged<_Filter> onSelected;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (selected) {
      _Filter.all => (
          'ทั้งหมด',
          Icons.view_list_rounded,
          const Color(0xFFFFD35A),
        ),
      _Filter.wins => (
          'ชนะ',
          Icons.emoji_events_rounded,
          const Color(0xFF67D9A4),
        ),
      _Filter.losses => (
          'แพ้',
          Icons.close_rounded,
          const Color(0xFFFFA6A6),
        ),
    };

    return SizedBox(
      height: AppSpacing.huge,
      child: Row(
        children: [
          Text(
            'ผลการแข่งขัน',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFD7E8FF),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          PopupMenuButton<_Filter>(
            key: const ValueKey('history-filter-menu'),
            initialValue: selected,
            tooltip: 'กรองผลการแข่งขัน',
            color: const Color(0xFF10283B),
            elevation: AppElevation.level3,
            position: PopupMenuPosition.under,
            onSelected: onSelected,
            itemBuilder: (context) => _Filter.values
                .map(
                  (filter) => PopupMenuItem<_Filter>(
                    key: ValueKey('history-filter-${filter.name}'),
                    value: filter,
                    child: _FilterMenuItem(
                      filter: filter,
                      selected: filter == selected,
                    ),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: Color(0xFFB8CEF0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterMenuItem extends StatelessWidget {
  const _FilterMenuItem({required this.filter, required this.selected});

  final _Filter filter;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (filter) {
      _Filter.all => (
          'ทั้งหมด',
          Icons.view_list_rounded,
          const Color(0xFFFFD35A),
        ),
      _Filter.wins => (
          'ชนะ',
          Icons.emoji_events_rounded,
          const Color(0xFF67D9A4),
        ),
      _Filter.losses => (
          'แพ้',
          Icons.close_rounded,
          const Color(0xFFFFA6A6),
        ),
    };
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label)),
        if (selected) Icon(Icons.check_rounded, color: color),
      ],
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({required this.history, required this.filter});

  final AsyncValue<List<MatchHistoryEntry>> history;
  final _Filter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) => history.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SkeletonList(rowHeight: 88),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: FantasyPanel(
            translucent: true,
            child: ErrorView(
              message: 'โหลดประวัติไม่ได้ ลองอีกครั้ง',
              onRetry: () => ref.invalidate(matchHistoryProvider),
            ),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FantasyPanel(
                translucent: true,
                child: EmptyView(
                  message: 'ยังไม่มีประวัติแมตช์ '
                      'เล่นแมตช์แรกเพื่อเริ่มเก็บสถิติ',
                  actionLabel: 'ค้นหาคู่แข่ง',
                  onAction: () => context.go('/lobby'),
                ),
              ),
            );
          }

          final rows = all.where((entry) {
            return switch (filter) {
              _Filter.all => true,
              _Filter.wins => entry.outcome == MatchOutcome.win,
              _Filter.losses => entry.outcome == MatchOutcome.loss,
            };
          }).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(matchHistoryProvider);
              await ref.read(matchHistoryProvider.future);
            },
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: const [
                      FantasyPanel(
                        translucent: true,
                        child: Center(child: Text('ไม่มีแมตช์ในหมวดนี้')),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => MatchListItem(
                      entry: rows[index],
                      onTap: () =>
                          context.push('/history/${rows[index].matchId}'),
                    ),
                  ),
          );
        },
      );
}
