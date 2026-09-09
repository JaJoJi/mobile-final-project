/// Riverpod wiring for the [WsClient].
///
/// * [wsClientProvider] — the singleton. Does **not** auto-connect;
///   the app shell calls `ref.read(wsClientProvider).connect()` once the
///   user is authenticated.
/// * [wsConnectionStateProvider] — reactive [WsConnectionState].
/// * [wsEventProvider] — raw `Map` stream for any `game:*` name.
/// * the typed `*Provider`s — decoded payloads for the events the UI
///   consumes directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/game_events.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import 'ws_client.dart';

/// Singleton WebSocket client. Disposed with the provider container.
final wsClientProvider = Provider<WsClient>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final client = WsClient(
    url: AppConfig.wsBaseUrl,
    getAccessToken: auth.getAccessToken,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Current connection state, starting from the client's state at
/// subscription time (no `loading` flash).
final wsConnectionStateProvider =
    StreamProvider<WsConnectionState>((ref) async* {
  final client = ref.watch(wsClientProvider);
  yield client.state;
  yield* client.connectionState;
});

/// Raw payload stream for an arbitrary event name. Prefer a typed
/// provider below when one exists.
///
/// ```dart
/// final phase = ref.watch(wsEventProvider('game:match:phase'));
/// ```
final wsEventProvider =
    StreamProvider.family<Map<String, dynamic>, String>((ref, name) {
  return ref.watch(wsClientProvider).stream(name);
});

/// `game:match:phase` → [MatchPhaseEvent].
final matchPhaseProvider = StreamProvider<MatchPhaseEvent>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.matchPhase, MatchPhaseEvent.fromJson);
});

/// `game:match:state` → [MatchState].
final matchStateProvider = StreamProvider<MatchState>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.matchState, MatchState.fromJson);
});

/// `game:combat:events` → [CombatEventBatch] (one per battle).
final combatEventsProvider = StreamProvider<CombatEventBatch>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.combatEvents, CombatEventBatch.fromJson);
});

/// `game:shop:offer` → [ShopOffersEvent] (the caller's private shop).
final shopOffersProvider = StreamProvider<ShopOffersEvent>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.shopOffer, ShopOffersEvent.fromJson);
});

/// `game:match:damage` → [MatchDamageEvent] (end-of-round result).
final matchDamageProvider = StreamProvider<MatchDamageEvent>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.matchDamage, MatchDamageEvent.fromJson);
});

/// `game:match:end` → [MatchEndEvent].
final matchEndProvider = StreamProvider<MatchEndEvent>((ref) {
  return ref
      .watch(wsClientProvider)
      .streamAs(GameEvents.matchEnd, MatchEndEvent.fromJson);
});

/// Every `game:error` envelope (auth failures included).
final gameErrorProvider = StreamProvider<GameError>((ref) {
  return ref.watch(wsClientProvider).errors;
});
