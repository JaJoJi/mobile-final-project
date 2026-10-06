import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Network-backed resources shown throughout the authenticated Player Hub.
enum PlayerHubResource { account, leaderboard, history, statistics }

/// Data stays immediately available while moving between tabs. A resource is
/// refreshed in the background only after this interval, or when a domain
/// event explicitly invalidates it.
const playerHubCacheTtl = Duration(minutes: 5);

final playerHubFreshnessProvider =
    StateNotifierProvider<PlayerHubFreshness, Map<PlayerHubResource, DateTime>>(
  (ref) => PlayerHubFreshness(),
);

class PlayerHubFreshness
    extends StateNotifier<Map<PlayerHubResource, DateTime>> {
  PlayerHubFreshness() : super(const {});

  void markFresh(PlayerHubResource resource, [DateTime? now]) {
    state = {...state, resource: now ?? DateTime.now()};
  }

  bool isStale(
    PlayerHubResource resource, {
    DateTime? now,
    Duration ttl = playerHubCacheTtl,
  }) {
    final fetchedAt = state[resource];
    return fetchedAt == null || (now ?? DateTime.now()).difference(fetchedAt) >= ttl;
  }

  void markStale(Iterable<PlayerHubResource> resources) {
    final next = {...state};
    for (final resource in resources) {
      next.remove(resource);
    }
    state = next;
  }

  void clear() => state = const {};
}
