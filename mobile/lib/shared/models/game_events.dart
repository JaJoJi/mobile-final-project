/// Barrel + wire names for every `game:*` WebSocket event.
///
/// Names mirror `docs/04-api-contracts.md` §2 one-to-one. Import this file
/// to get both the string constants and every typed payload model.
library;

export 'combat_event.dart';
export 'game_error.dart';
export 'match_damage.dart';
export 'match_end.dart';
export 'match_phase.dart';
export 'match_state.dart';
export 'shop_offer.dart';
export 'unit.dart';

/// Server → client event names.
abstract final class GameEvents {
  static const matchPhase = 'game:match:phase';
  static const shopOffer = 'game:shop:offer';
  static const matchState = 'game:match:state';
  static const combatEvents = 'game:combat:events';
  static const matchDamage = 'game:match:damage';
  static const matchEnd = 'game:match:end';
  static const error = 'game:error';

  /// Every server → client name, for diagnostics / logging.
  static const all = <String>[
    matchPhase,
    shopOffer,
    matchState,
    combatEvents,
    matchDamage,
    matchEnd,
    error,
  ];
}

/// Client → server event names.
abstract final class GameActions {
  static const matchmakingJoin = 'game:matchmaking:join';
  static const matchmakingLeave = 'game:matchmaking:leave';
  static const shopBuy = 'game:shop:buy';
  static const shopSell = 'game:shop:sell';
  static const shopRefresh = 'game:shop:refresh';
  static const shopFuse = 'game:shop:fuse';
  static const matchPlace = 'game:match:place';
  static const matchReady = 'game:match:ready';
  static const matchCombatDone = 'game:match:combat_done';
}
