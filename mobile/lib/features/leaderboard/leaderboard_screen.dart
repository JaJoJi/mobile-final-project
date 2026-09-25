import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../player_hub/player_crest.dart';
import '../player_hub/player_hub_fixture_provider.dart';
import '../player_hub/player_hub_models.dart';
import '../player_hub/player_hub_shell.dart';
import '../profile/player_hub_navigation.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  static const path = '/leaderboard';

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(leaderboardSourceProvider);
    return PlayerHubShell(
      title: 'ตารางอันดับ',
      subtitle: 'ผู้บัญชาการแห่งสนาม · เรียงตามเรตติ้ง',
      headerAction: TextButton(
        onPressed: () => context.go('/profile'),
        child: const Text('โปรไฟล์ของฉัน'),
      ),
      body: source.when(
        loading: () => const Center(child: Text('กำลังโหลดข้อมูล…')),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('โหลดข้อมูลไม่สำเร็จ'),
              TextButton(
                onPressed: () => ref.invalidate(leaderboardSourceProvider),
                child: const Text('ลองอีกครั้ง'),
              ),
            ],
          ),
        ),
        data: _buildContent,
      ),
      navigation: const PlayerHubNavigation(selected: PlayerHubTab.leaderboard),
    );
  }

  Widget _buildContent(LeaderboardViewData data) {
    final rows = data.entries.take(_showAll ? data.entries.length : 5).toList();
    final champion = data.entries.isEmpty ? null : data.entries.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final championCard = champion == null
            ? null
            : _ChampionCard(entry: champion, compact: !wide);
        final ranking = _RankingPanel(
          entries: rows,
          currentPlayer: data.currentPlayer,
          showMore: !_showAll && data.entries.length > 5,
          allShown: _showAll,
          onShowMore: () => setState(() => _showAll = true),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: Text('ยังไม่มีข้อมูลอันดับ')),
                )
              else if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 270, child: championCard!),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(child: ranking),
                  ],
                )
              else ...[
                championCard!,
                const SizedBox(height: AppSpacing.lg),
                ranking,
              ],
              const SizedBox(height: AppSpacing.lg),
              _CurrentRank(entry: data.currentPlayer),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'อันดับของคุณแสดงเสมอ แม้อยู่นอกรายการที่โหลด',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChampionCard extends StatelessWidget {
  const _ChampionCard({required this.entry, required this.compact});
  final LeaderboardEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x88685024), Color(0xE60C2034)],
          ),
          border: Border.all(color: const Color(0x80F2C14E)),
        ),
        child: compact
            ? Row(
                key: const ValueKey('leaderboard-champion-compact'),
                children: [
                  PlayerCrest(label: '${entry.rank}', compact: true),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ChampionDetails(entry: entry, compact: true),
                  ),
                ],
              )
            : Column(
                children: [
                  const Text('อันดับหนึ่ง'),
                  const SizedBox(height: AppSpacing.md),
                  PlayerCrest(label: '${entry.rank}'),
                  const SizedBox(height: AppSpacing.md),
                  _ChampionDetails(entry: entry),
                ],
              ),
      );
}

class _ChampionDetails extends StatelessWidget {
  const _ChampionDetails({required this.entry, this.compact = false});
  final LeaderboardEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text('อันดับหนึ่ง', style: Theme.of(context).textTheme.bodySmall),
          Text(entry.username, style: Theme.of(context).textTheme.titleLarge),
          Text(
            _formatRating(entry.rating),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFFF2C14E),
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            'เรตติ้ง',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

class _RankingPanel extends StatelessWidget {
  const _RankingPanel({
    required this.entries,
    required this.currentPlayer,
    required this.showMore,
    required this.allShown,
    required this.onShowMore,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry currentPlayer;
  final bool showMore;
  final bool allShown;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xED0B1C2C),
          border: Border.all(color: const Color(0x66829EB2)),
        ),
        child: Column(
          children: [
            const _RankingHeader(),
            for (final entry in entries)
              _RankingRow(
                entry: entry,
                isCurrentPlayer: entry.rank == currentPlayer.rank &&
                    entry.username == currentPlayer.username,
              ),
            if (showMore)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: OutlinedButton(
                  onPressed: onShowMore,
                  child: const Text('โหลดเพิ่มเติม'),
                ),
              ),
            if (allShown)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('แสดงข้อมูลตัวอย่างครบแล้ว'),
              ),
          ],
        ),
      );
}

class _RankingHeader extends StatelessWidget {
  const _RankingHeader();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF081522)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text('อันดับ')),
              Expanded(child: Text('ผู้เล่น')),
              Text('เรตติ้ง'),
            ],
          ),
        ),
      );
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry, required this.isCurrentPlayer});
  final LeaderboardEntry entry;
  final bool isCurrentPlayer;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        key: isCurrentPlayer ? const ValueKey('leaderboard-self-row') : null,
        decoration: BoxDecoration(
          color: isCurrentPlayer ? const Color(0x1FF2C14E) : null,
          border: Border(
            top: const BorderSide(color: Color(0x33829EB2)),
            left: isCurrentPlayer
                ? const BorderSide(color: Color(0xFFF2C14E), width: 3)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                '${entry.rank}',
                style: const TextStyle(color: Color(0xFFF2C14E)),
              ),
            ),
            Expanded(
              child: Text(entry.username, overflow: TextOverflow.ellipsis),
            ),
            Text(_formatRating(entry.rating)),
          ],
        ),
      );
}

class _CurrentRank extends StatelessWidget {
  const _CurrentRank({required this.entry});
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: const Color(0xFF253342),
          border: Border.all(color: const Color(0x99F2C14E)),
        ),
        child: Row(
          children: [
            Text(
              '#${entry.rank}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFF2C14E),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.username),
                  const Text('อันดับของคุณ'),
                ],
              ),
            ),
            Text(_formatRating(entry.rating)),
          ],
        ),
      );
}

String _formatRating(int rating) => rating.toString().replaceFirstMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => ',',
    );
