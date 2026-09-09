/// `game:error` — the server rejected an action or the connection.
///
/// Mirrors `docs/04-api-contracts.md` §2 — `game:error` and §5 (codes).
library;

class GameError implements Exception {
  const GameError({
    required this.code,
    this.message,
    this.clientActionId,
  });

  /// Stable machine code, e.g. `auth.invalid`, `shop.insufficient_gold`,
  /// `match.round_mismatch`. See `docs/04-api-contracts.md` §5.
  final String code;

  /// Optional human-readable detail.
  final String? message;

  /// Echoes the `clientActionId` of the action that failed, when the
  /// failure is tied to one.
  final String? clientActionId;

  /// `auth.invalid` / `auth.expired` — the socket will be disconnected by
  /// the server and must not simply reconnect with the same token.
  bool get isAuth => code.startsWith('auth.');

  /// `rate.limited` — back off before retrying.
  bool get isRateLimit => code == 'rate.limited';

  factory GameError.fromJson(Map<String, dynamic> j) => GameError(
        code: j['code'] as String? ?? 'unknown',
        message: j['message'] as String?,
        clientActionId: j['clientActionId'] as String?,
      );

  @override
  String toString() => 'GameError($code${message == null ? '' : ': $message'})';
}
