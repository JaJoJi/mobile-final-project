import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../player_hub/player_hub_cache_state.dart';

/// The signed-in player's aggregate gameplay statistics.
final myStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final value = await ref.read(apiClientProvider).getMyStats();
  ref
      .read(playerHubFreshnessProvider.notifier)
      .markFresh(PlayerHubResource.statistics);
  return value;
});
