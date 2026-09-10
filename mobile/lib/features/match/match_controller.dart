import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ws/ws_client.dart';
import '../../core/ws/ws_providers.dart';
import '../../shared/models/game_events.dart';

enum RosterArea { board, bench }

class UnitSelection {
  const UnitSelection(this.area, this.slot);

  final RosterArea area;
  final int slot;
}

class MatchViewState {
  const MatchViewState({
    this.phase,
    this.match,
    this.shop,
    this.damage,
    this.end,
    this.selection,
    this.pendingActionId,
    this.errorMessage,
    this.refreshUsed = false,
    this.readySubmitted = false,
    this.combatDoneSubmitted = false,
  });

  final MatchPhaseEvent? phase;
  final MatchState? match;
  final ShopOffersEvent? shop;
  final MatchDamageEvent? damage;
  final MatchEndEvent? end;
  final UnitSelection? selection;
  final String? pendingActionId;
  final String? errorMessage;
  final bool refreshUsed;
  final bool readySubmitted;
  final bool combatDoneSubmitted;

  bool get loading => phase == null || match == null;
  bool get canAct =>
      phase?.phase == GamePhase.shopPlace && pendingActionId == null;

  MatchViewState copyWith({
    MatchPhaseEvent? phase,
    MatchState? match,
    ShopOffersEvent? shop,
    MatchDamageEvent? damage,
    MatchEndEvent? end,
    UnitSelection? selection,
    String? pendingActionId,
    String? errorMessage,
    bool? refreshUsed,
    bool? readySubmitted,
    bool? combatDoneSubmitted,
    bool clearSelection = false,
    bool clearPending = false,
    bool clearError = false,
    bool clearDamage = false,
  }) =>
      MatchViewState(
        phase: phase ?? this.phase,
        match: match ?? this.match,
        shop: shop ?? this.shop,
        damage: clearDamage ? null : damage ?? this.damage,
        end: end ?? this.end,
        selection: clearSelection ? null : selection ?? this.selection,
        pendingActionId:
            clearPending ? null : pendingActionId ?? this.pendingActionId,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        refreshUsed: refreshUsed ?? this.refreshUsed,
        readySubmitted: readySubmitted ?? this.readySubmitted,
        combatDoneSubmitted: combatDoneSubmitted ?? this.combatDoneSubmitted,
      );
}

final matchControllerProvider = StateNotifierProvider.autoDispose
    .family<MatchController, MatchViewState, String>((ref, matchId) {
  return MatchController(
    matchId: matchId,
    client: ref.watch(wsClientProvider),
  );
});

/// Owns the authoritative match snapshot plus one in-flight optimistic action.
/// Combat outcomes are deliberately never calculated here.
class MatchController extends StateNotifier<MatchViewState> {
  MatchController({required this.matchId, required WsClient client})
      : _client = client,
        super(const MatchViewState()) {
    _subscriptions.addAll([
      client
          .streamAsLatest(GameEvents.matchPhase, MatchPhaseEvent.fromJson)
          .listen(_onPhase),
      client
          .streamAsLatest(GameEvents.matchState, MatchState.fromJson)
          .listen(_onMatchState),
      client
          .streamAsLatest(GameEvents.shopOffer, ShopOffersEvent.fromJson)
          .listen(_onShop),
      client
          .streamAsLatest(GameEvents.matchDamage, MatchDamageEvent.fromJson)
          .listen(_onDamage),
      client
          .streamAsLatest(GameEvents.matchEnd, MatchEndEvent.fromJson)
          .listen(_onEnd),
      client.errors.listen(_onError),
    ]);
  }

  final String matchId;
  final WsClient _client;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Random _random = Random.secure();
  MatchViewState? _rollback;

  void _onPhase(MatchPhaseEvent event) {
    if (event.matchId != matchId) return;
    final roundChanged = state.phase?.round != event.round;
    final side = state.match?.yourSide;
    final readyFromServer = side == null ? null : _phaseReady(event, side);
    state = state.copyWith(
      phase: event,
      refreshUsed: roundChanged ? false : null,
      readySubmitted: event.phase == GamePhase.shopPlace
          ? readyFromServer ?? (roundChanged ? false : state.readySubmitted)
          : false,
      combatDoneSubmitted:
          event.phase == GamePhase.battle ? state.combatDoneSubmitted : false,
      clearDamage: event.phase == GamePhase.shopPlace,
      clearError: true,
    );
  }

  void _onMatchState(MatchState event) {
    if (event.matchId != matchId) return;
    final firstSnapshot = state.match == null;
    final readyFromServer = firstSnapshot && state.phase != null
        ? _phaseReady(state.phase!, event.yourSide)
        : null;
    _rollback = null;
    state = state.copyWith(
      match: event,
      readySubmitted: readyFromServer,
      clearPending: true,
      clearError: true,
    );
  }

  void _onShop(ShopOffersEvent event) {
    if (event.matchId != matchId) return;
    final isRefresh = state.shop != null && state.shop?.round == event.round;
    state = state.copyWith(
      shop: event,
      refreshUsed: isRefresh || state.refreshUsed,
      clearPending: isRefresh,
      clearError: true,
    );
  }

  void _onDamage(MatchDamageEvent event) {
    if (event.matchId == matchId) state = state.copyWith(damage: event);
  }

  void _onEnd(MatchEndEvent event) {
    if (event.matchId == matchId) state = state.copyWith(end: event);
  }

  void _onError(GameError error) {
    if (error.clientActionId != null &&
        error.clientActionId == state.pendingActionId &&
        _rollback != null) {
      final restored = _rollback!;
      _rollback = null;
      state = restored.copyWith(
        errorMessage: gameErrorMessage(error.code),
        clearPending: true,
      );
      return;
    }
    state = state.copyWith(errorMessage: gameErrorMessage(error.code));
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clearRoundResult() => state = state.copyWith(clearDamage: true);

  void select(RosterArea area, int slot) {
    if (!state.canAct) return;
    final unit = _unitAt(area, slot);
    if (unit == null) {
      final selected = state.selection;
      if (selected != null) place(area, slot);
      return;
    }
    state = state.copyWith(selection: UnitSelection(area, slot));
  }

  void buy(int offerIndex) {
    final match = state.match;
    final shop = state.shop;
    if (!state.canAct || match == null || shop == null) return;
    if (offerIndex < 0 || offerIndex >= shop.offers.length) return;
    final offer = shop.offers[offerIndex];
    if (offer == null) return;
    final price = unitPrice(offer.unitId);
    if (match.roster.gold < price) {
      state = state.copyWith(errorMessage: 'ทองไม่พอ ต้องการ $price ทอง');
      return;
    }
    final benchSlot = match.roster.bench.indexWhere((unit) => unit == null);
    if (benchSlot < 0) {
      state = state.copyWith(
        errorMessage: 'ช่องยูนิตรอจัดทีมเต็ม ขายหรือย้ายยูนิตก่อน',
      );
      return;
    }

    final actionId = _actionId();
    _beginOptimistic();
    final offers = List<ShopOffer?>.of(shop.offers)..[offerIndex] = null;
    final bench = List<Unit?>.of(match.roster.bench)
      ..[benchSlot] = Unit(
        instanceId: 'pending-$actionId',
        unitId: offer.unitId,
        star: offer.star,
        hp: unitMaxHp(offer.unitId),
        maxHp: unitMaxHp(offer.unitId),
      );
    state = state.copyWith(
      shop: ShopOffersEvent(
        matchId: shop.matchId,
        round: shop.round,
        offers: offers,
      ),
      match: _copyMatch(match, bench: bench, gold: match.roster.gold - price),
      pendingActionId: actionId,
      clearError: true,
    );
    _client.emit(GameActions.shopBuy, {
      'round': match.round,
      'offerIndex': offerIndex,
      'clientActionId': actionId,
    });
  }

  void refresh() {
    final match = state.match;
    if (!state.canAct || state.refreshUsed || match == null) return;
    final actionId = _actionId();
    _beginOptimistic();
    state = state.copyWith(
      refreshUsed: true,
      pendingActionId: actionId,
      clearError: true,
    );
    _client.emit(GameActions.shopRefresh, {
      'round': match.round,
      'clientActionId': actionId,
    });
  }

  void toggleReady() {
    final match = state.match;
    if (!state.canAct || match == null || match.readyCount >= 2) return;
    final nextReady = !state.readySubmitted;
    final actionId = _actionId();
    _beginOptimistic();
    final nextCount = (match.readyCount + (nextReady ? 1 : -1)).clamp(0, 2);
    state = state.copyWith(
      readySubmitted: nextReady,
      match: _copyMatch(match, readyCount: nextCount),
      pendingActionId: actionId,
      clearError: true,
    );
    _client.emit(GameActions.matchReady, {
      'round': match.round,
      'ready': nextReady,
      'clientActionId': actionId,
    });
  }

  /// Kept for callers built against the first FE04 draft.
  void ready() => toggleReady();

  /// Skips local playback by acknowledging the server's combat batch.
  /// The server still waits for both players (or its 60-second fallback),
  /// so one player cannot force the other player to skip.
  void skipCombat() {
    final phase = state.phase;
    if (phase?.phase != GamePhase.battle || state.combatDoneSubmitted) return;
    state = state.copyWith(combatDoneSubmitted: true, clearError: true);
    _client.emit(GameActions.matchCombatDone, {
      'matchId': matchId,
      'round': phase!.round,
      'clientActionId': _actionId(),
    });
  }

  void place(RosterArea target, int slot, [UnitSelection? from]) {
    final match = state.match;
    final selected = from ?? state.selection;
    if (!state.canAct || match == null || selected == null) return;
    final unit = _unitAt(selected.area, selected.slot);
    if (unit == null || _unitAt(target, slot) != null) return;

    final board = List<Unit?>.of(match.roster.board);
    final bench = List<Unit?>.of(match.roster.bench);
    final source = selected.area == RosterArea.board ? board : bench;
    final destination = target == RosterArea.board ? board : bench;
    source[selected.slot] = null;
    destination[slot] = unit;

    final actionId = _actionId();
    _beginOptimistic();
    state = state.copyWith(
      match: _copyMatch(match, board: board, bench: bench),
      pendingActionId: actionId,
      clearSelection: true,
      clearError: true,
    );
    _client.emit(GameActions.matchPlace, {
      'round': match.round,
      'unitInstanceId': unit.instanceId,
      'target': target.name,
      'slot': slot,
      'clientActionId': actionId,
    });
  }

  void sell(RosterArea area, int slot) {
    final match = state.match;
    final unit = _unitAt(area, slot);
    if (!state.canAct || match == null || unit == null) return;
    final board = List<Unit?>.of(match.roster.board);
    final bench = List<Unit?>.of(match.roster.bench);
    (area == RosterArea.board ? board : bench)[slot] = null;
    final actionId = _actionId();
    _beginOptimistic();
    state = state.copyWith(
      match: _copyMatch(
        match,
        board: board,
        bench: bench,
        gold: match.roster.gold + unitPrice(unit.unitId),
      ),
      pendingActionId: actionId,
      clearSelection: true,
      clearError: true,
    );
    _client.emit(GameActions.shopSell, {
      'round': match.round,
      'source': area.name,
      'slot': slot,
      'clientActionId': actionId,
    });
  }

  void fuse(Unit unit) {
    final match = state.match;
    if (!state.canAct || match == null) return;
    final actionId = _actionId();
    _beginOptimistic();
    state = state.copyWith(
      pendingActionId: actionId,
      clearError: true,
    );
    _client.emit(GameActions.shopFuse, {
      'round': match.round,
      'unitId': unit.unitId.toJson(),
      'clientActionId': actionId,
    });
  }

  Unit? _unitAt(RosterArea area, int slot) {
    final roster = state.match?.roster;
    if (roster == null) return null;
    final units = area == RosterArea.board ? roster.board : roster.bench;
    return slot >= 0 && slot < units.length ? units[slot] : null;
  }

  void _beginOptimistic() {
    _rollback = state;
  }

  MatchState _copyMatch(
    MatchState source, {
    List<Unit?>? board,
    List<Unit?>? bench,
    int? gold,
    int? readyCount,
  }) =>
      MatchState(
        matchId: source.matchId,
        round: source.round,
        yourSide: source.yourSide,
        roster: PlayerRoster(
          board: board ?? source.roster.board,
          bench: bench ?? source.roster.bench,
          gold: gold ?? source.roster.gold,
          hp: source.roster.hp,
        ),
        opponent: source.opponent,
        readyCount: readyCount ?? source.readyCount,
      );

  bool _phaseReady(MatchPhaseEvent phase, MatchSide side) {
    final index = side == MatchSide.p1 ? 0 : 1;
    return index < phase.players.length && phase.players[index].ready;
  }

  String _actionId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

int unitPrice(UnitId unitId) => switch (unitId) {
      UnitId.fighter || UnitId.healer => 1,
      UnitId.ranger || UnitId.tank => 2,
    };

int unitMaxHp(UnitId unitId) => switch (unitId) {
      UnitId.fighter => 100,
      UnitId.healer => 70,
      UnitId.ranger => 60,
      UnitId.tank => 150,
    };

String gameErrorMessage(String code) => switch (code) {
      'shop.insufficient_gold' => 'ทองไม่พอ',
      'shop.refresh_used' => 'รีเฟรชได้รอบละครั้ง',
      'shop.roster_full' => 'ช่องยูนิตรอจัดทีมเต็ม ขายหรือย้ายยูนิตก่อน',
      'place.slot_occupied' => 'ช่องนี้มีตัวอยู่แล้ว',
      'place.slot_out_of_range' => 'ช่องที่เลือกใช้งานไม่ได้',
      'match.not_your_turn' => 'ทำไม่ได้ในเฟสนี้',
      'match.round_mismatch' => 'รอบเปลี่ยนแล้ว กรุณาลองใหม่',
      'rate.limited' => 'กดเร็วเกินไป รอสักครู่',
      _ => 'ทำรายการไม่สำเร็จ กรุณาลองใหม่',
    };
