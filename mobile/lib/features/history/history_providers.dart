import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../player_hub/player_hub_cache_state.dart';
import 'match_models.dart';

/// `GET /match/history` → the caller's recent matches, newest first.
final matchHistoryProvider = FutureProvider<List<MatchHistoryEntry>>((ref) async {
  final rows = await ref.read(apiClientProvider).getMatchHistory();
  final entries = rows.map(MatchHistoryEntry.fromJson).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  ref
      .read(playerHubFreshnessProvider.notifier)
      .markFresh(PlayerHubResource.history);
  return entries;
});

/// `GET /match/:matchId` → one match's detail.
final matchDetailProvider = FutureProvider.autoDispose
    .family<MatchDetail, String>((ref, matchId) async {
  final json = await ref.read(apiClientProvider).getMatchDetail(matchId);
  return MatchDetail.fromJson(json);
});
