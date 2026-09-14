import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import 'history_providers.dart';
import 'match_list_item.dart';
import 'match_models.dart';

/// `/history` — the caller's past matches (design spec §4.6).
class HistoryListScreen extends ConsumerStatefulWidget {
  const HistoryListScreen({super.key});

  static const path = '/history';

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

enum _Filter { all, wins, losses }

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  _Filter _filter = _Filter.all;

  bool _matchesFilter(MatchHistoryEntry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.wins => e.outcome == MatchOutcome.win,
        _Filter.losses => e.outcome == MatchOutcome.loss,
      };

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(matchHistoryProvider);

    return AppScaffold(
      title: 'ประวัติการแข่งขัน',
      padded: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppTabBar(
              currentIndex: _filter.index,
              onChanged: (i) => setState(() => _filter = _Filter.values[i]),
              tabs: const [
                AppTab(label: 'ทั้งหมด', icon: Icons.list),
                AppTab(label: 'ชนะ', icon: Icons.emoji_events_outlined),
                AppTab(label: 'แพ้', icon: Icons.close),
              ],
            ),
          ),
          Expanded(
            child: history.when(
              loading: () => const SkeletonList(rowHeight: 72),
              error: (_, __) => ErrorView(
                message: 'โหลดประวัติไม่ได้ ลองอีกครั้ง',
                onRetry: () => ref.invalidate(matchHistoryProvider),
              ),
              data: (all) {
                if (all.isEmpty) {
                  return EmptyView(
                    message: 'ยังไม่มีประวัติแมตช์ '
                        'เล่นแมตช์แรกเพื่อเริ่มเก็บสถิติ',
                    actionLabel: 'ค้นหาคู่แข่ง',
                    onAction: () => context.go('/lobby'),
                  );
                }
                final rows = all.where(_matchesFilter).toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(matchHistoryProvider);
                    await ref.read(matchHistoryProvider.future);
                  },
                  child: rows.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: AppSpacing.huge),
                            Center(
                              child: Text(
                                'ไม่มีแมตช์ในหมวดนี้',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => MatchListItem(
                            entry: rows[i],
                            onTap: () =>
                                context.push('/history/${rows[i].matchId}'),
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
