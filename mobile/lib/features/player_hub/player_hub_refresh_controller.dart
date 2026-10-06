import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../history/history_providers.dart';
import '../lobby/profile_card.dart';
import '../profile/profile_providers.dart';
import 'player_hub_cache_state.dart';
import 'player_hub_fixture_provider.dart';

final playerHubRefreshControllerProvider = Provider<PlayerHubRefreshController>(
  PlayerHubRefreshController.new,
);

/// Owns the cache invalidation rules for the Player Hub.
///
/// Navigation calls [refreshIfStale], while domain events (match completion,
/// profile edits, sign-out) call one of the explicit invalidation methods.
class PlayerHubRefreshController {
  PlayerHubRefreshController(this.ref);

  final Ref ref;

  void refreshIfStale(Iterable<PlayerHubResource> resources) {
    final freshness = ref.read(playerHubFreshnessProvider.notifier);
    for (final resource in resources) {
      if (freshness.isStale(resource)) _refresh(resource);
    }
  }

  void refreshStaleAll() => refreshIfStale(PlayerHubResource.values);

  void invalidateAfterMatch() {
    invalidate(const {
      PlayerHubResource.account,
      PlayerHubResource.leaderboard,
      PlayerHubResource.history,
      PlayerHubResource.statistics,
    });
  }

  void invalidateProfile() {
    invalidate(const {
      PlayerHubResource.account,
      PlayerHubResource.leaderboard,
      PlayerHubResource.statistics,
    });
  }

  void invalidate(Iterable<PlayerHubResource> resources) {
    final values = resources.toSet();
    ref.read(playerHubFreshnessProvider.notifier).markStale(values);
    for (final resource in values) {
      _refresh(resource);
    }
  }

  void prepareForSignIn() {
    ref.read(playerHubFreshnessProvider.notifier).clear();
    for (final resource in PlayerHubResource.values) {
      _invalidateProvider(resource);
    }
  }

  void clearFreshnessForSignOut() {
    ref.read(playerHubFreshnessProvider.notifier).clear();
  }

  void _refresh(PlayerHubResource resource) {
    _invalidateProvider(resource);
    // If the screen is currently mounted Riverpod retains its previous value
    // while this recomputation runs, so there is no full-screen loading flash.
  }

  void _invalidateProvider(PlayerHubResource resource) {
    switch (resource) {
      case PlayerHubResource.account:
        if (ref.exists(currentUserProvider)) {
          ref.invalidate(currentUserProvider);
        }
      case PlayerHubResource.leaderboard:
        if (ref.exists(leaderboardSourceProvider)) {
          ref.invalidate(leaderboardSourceProvider);
        }
      case PlayerHubResource.history:
        if (ref.exists(matchHistoryProvider)) {
          ref.invalidate(matchHistoryProvider);
        }
      case PlayerHubResource.statistics:
        if (ref.exists(myStatsProvider)) {
          ref.invalidate(myStatsProvider);
        }
    }
  }
}
