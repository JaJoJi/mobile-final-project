import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/fantasy_page.dart';
import '../../core/widgets/state_views.dart';
import '../lobby/player_hub_header.dart';
import '../lobby/player_hub_navigation.dart';
import '../player_hub/player_hub_fixture_provider.dart';
import '../player_hub/player_hub_models.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  static const path = '/leaderboard';

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _showAll = false;
  bool _loadingMore = false;
  String? _loadMoreError;
  final List<LeaderboardEntry> _extraEntries = [];

  Future<void> _loadMore(LeaderboardViewData data) async {
    if (_loadingMore ||
        data.entries.length + _extraEntries.length >= data.total) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = LeaderboardViewData.fromJson(
        await ref.read(apiClientProvider).getLeaderboard(
              limit: data.limit,
              offset: data.offset + data.entries.length + _extraEntries.length,
            ),
      );
      if (mounted) setState(() => _extraEntries.addAll(next.entries));
    } catch (_) {
      if (mounted) setState(() => _loadMoreError = 'โหลดอันดับเพิ่มไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleExpanded(LeaderboardViewData data) async {
    if (_showAll) {
      setState(() => _showAll = false);
      return;
    }

    setState(() => _showAll = true);
    if (data.entries.length + _extraEntries.length <= 5) {
      await _loadMore(data);
    }
  }

  void _retry() {
    setState(() {
      _showAll = false;
      _extraEntries.clear();
      _loadMoreError = null;
    });
    ref.invalidate(leaderboardSourceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(leaderboardSourceProvider);

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
                const _LeaderboardHeader(),
                Expanded(
                  child: source.when(
                    loading: () => const _LeaderboardSkeleton(),
                    error: (_, __) => Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: FantasyPanel(
                        translucent: true,
                        child: ErrorView(
                          message: 'โหลดข้อมูลไม่สำเร็จ',
                          onRetry: _retry,
                        ),
                      ),
                    ),
                    data: _buildContent,
                  ),
                ),
                const PlayerHubNavigation(selected: PlayerHubTab.home),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(LeaderboardViewData data) {
    final loaded = [...data.entries, ..._extraEntries];
    final rows = loaded.take(_showAll ? loaded.length : 5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _CurrentRankCard(entry: data.currentPlayer),
        const SizedBox(height: AppSpacing.lg),
        const _RankingSectionHeader(),
        const SizedBox(height: AppSpacing.sm),
        if (rows.isEmpty)
          const FantasyPanel(
            translucent: true,
            child: Center(child: Text('ยังไม่มีข้อมูลอันดับ')),
          )
        else
          FantasyPanel(
            translucent: true,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  _RankingRow(
                    entry: rows[index],
                    displayRank: index + 1,
                    isCurrentPlayer:
                        rows[index].rank == data.currentPlayer.rank &&
                            rows[index].username == data.currentPlayer.username,
                  ),
                  if (index != rows.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
                if (!_showAll &&
                    (loaded.length > 5 || loaded.length < data.total)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _loadingMore ? null : () => _toggleExpanded(data),
                      icon: _loadingMore
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(
                        _loadingMore ? 'กำลังโหลด…' : 'โหลดเพิ่มเติม',
                      ),
                    ),
                  ),
                ],
                if (_showAll) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _loadingMore ? null : () => _toggleExpanded(data),
                          icon: const Icon(Icons.expand_less_rounded),
                          label: const Text('ย่อรายการ'),
                        ),
                      ),
                      if (loaded.length < data.total) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed:
                                _loadingMore ? null : () => _loadMore(data),
                            icon: _loadingMore
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded),
                            label: Text(
                              _loadingMore ? 'กำลังโหลด…' : 'โหลดเพิ่ม',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (_loadMoreError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _loadMoreError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader();

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'กลับ',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/lobby');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.emoji_events_rounded,
                size: 30,
                color: Color(0xFFFFD35A),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'ตารางอันดับ',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFFFF5D6),
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _RankingSectionHeader extends StatelessWidget {
  const _RankingSectionHeader();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(
            Icons.format_list_numbered_rounded,
            size: 20,
            color: Color(0xFFFFD35A),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'อันดับผู้เล่น',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFFFF5D6),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      );
}

(Color, IconData) _rankAppearance(int rank) => switch (rank) {
      1 => (const Color(0xFFFFD35A), Icons.emoji_events_rounded),
      2 => (const Color(0xFFC9D7E5), Icons.workspace_premium_rounded),
      3 => (const Color(0xFFD99A62), Icons.military_tech_rounded),
      _ => (const Color(0xFF8FA8BE), Icons.shield_outlined),
    };

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.entry,
    required this.displayRank,
    required this.isCurrentPlayer,
  });

  final LeaderboardEntry entry;
  final int displayRank;
  final bool isCurrentPlayer;

  @override
  Widget build(BuildContext context) {
    final (medalColor, medalIcon) = _rankAppearance(displayRank);

    return Container(
      key: isCurrentPlayer ? const ValueKey('leaderboard-self-row') : null,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color:
            isCurrentPlayer ? const Color(0x331E6B88) : const Color(0x99102538),
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: isCurrentPlayer
              ? const Color(0xB359B7E8)
              : const Color(0x526FA5C4),
        ),
      ),
      child: Row(
        children: [
          _RankMedal(rank: displayRank, color: medalColor, icon: medalIcon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFFF4F7FB),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (isCurrentPlayer) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x3359B7E8),
                      borderRadius: AppRadius.allFull,
                    ),
                    child: Text(
                      'คุณ',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF9DDCFF),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _RatingBadge(rating: entry.rating, accent: medalColor),
        ],
      ),
    );
  }
}

class _RankMedal extends StatelessWidget {
  const _RankMedal({
    required this.rank,
    required this.color,
    required this.icon,
  });

  final int rank;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.68)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 27, color: color.withValues(alpha: 0.22)),
            Text(
              '$rank',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      );
}

class _CurrentRankCard extends StatelessWidget {
  const _CurrentRankCard({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('leaderboard-current-rank-card'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xCC16384D), Color(0xED0A1B2E)],
          ),
          borderRadius: AppRadius.allLg,
          border: Border.all(color: const Color(0x9959B7E8)),
        ),
        child: Row(
          children: [
            _RankMedal(
              rank: entry.rank,
              color: _rankAppearance(entry.rank).$1,
              icon: _rankAppearance(entry.rank).$2,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'อันดับของคุณ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB8CEF0),
                        ),
                  ),
                  Text(
                    entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            _RatingBadge(
              rating: entry.rating,
              accent: _rankAppearance(entry.rank).$1,
            ),
          ],
        ),
      );
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating, required this.accent});

  final int rating;
  final Color accent;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'เรตติ้ง ${_formatRating(rating)}',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC071726),
            borderRadius: AppRadius.allFull,
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.military_tech_rounded, size: 16, color: accent),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                _formatRating(rating),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'กำลังโหลดข้อมูล…',
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            ExcludeSemantics(child: SkeletonBox(height: 96)),
            SizedBox(height: AppSpacing.lg),
            ExcludeSemantics(child: SkeletonBox(height: 24, width: 160)),
            SizedBox(height: AppSpacing.sm),
            ExcludeSemantics(child: SkeletonBox(height: 64)),
            SizedBox(height: AppSpacing.sm),
            ExcludeSemantics(child: SkeletonBox(height: 64)),
            SizedBox(height: AppSpacing.sm),
            ExcludeSemantics(child: SkeletonBox(height: 64)),
          ],
        ),
      );
}

String _formatRating(int rating) => rating.toString().replaceFirstMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => ',',
    );
