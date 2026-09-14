/// Singleton WebSocket client for the `/game` namespace.
///
/// Wraps a [WsTransport] (socket.io in production) and exposes:
///   * [connect] / [disconnect] — lifecycle, with a `Future` that
///     completes on the first successful connect and rejects with a
///     [WsAuthException] if the server rejects the JWT.
///   * [connectionState] — a broadcast stream of [WsConnectionState] for
///     reactive UI ("Connection lost, retrying…").
///   * [stream] / [streamAs] — one broadcast stream per `game:*` event,
///     created lazily and shared by every listener.
///   * [errors] — every `game:error` envelope the server sends.
///   * [emit] — typed-name client → server sends.
///
/// Reconnect with exponential backoff (1s → 30s cap) is the transport's
/// job; this class only tracks and surfaces the resulting state.
library;

import 'dart:async';

import '../../shared/models/game_events.dart';
import 'ws_transport.dart';

export 'ws_transport.dart' show WsTransport, WsTokenProvider;

enum WsConnectionState {
  /// Never connected, or [WsClient.disconnect] / an auth failure closed it.
  disconnected,

  /// [WsClient.connect] called, handshake in flight.
  connecting,

  /// Live.
  connected,

  /// Dropped; the transport is retrying with backoff.
  reconnecting,
}

/// The server rejected the socket's JWT (`game:error` with an `auth.*`
/// code). The connection is closed and will **not** be retried — the
/// caller must obtain a fresh token and call [WsClient.connect] again.
class WsAuthException implements Exception {
  const WsAuthException(this.code, [this.message]);

  /// `auth.invalid` or `auth.expired`.
  final String code;
  final String? message;

  @override
  String toString() =>
      'WsAuthException($code${message == null ? '' : ': $message'})';
}

class WsClient {
  WsClient({
    required String url,
    required WsTokenProvider getAccessToken,
    WsTransport? transport,
  }) : _transport = transport ??
            SocketIoTransport(baseUrl: url, tokenProvider: getAccessToken) {
    _wire();
  }

  final WsTransport _transport;

  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();
  final StreamController<GameError> _errorController =
      StreamController<GameError>.broadcast();
  final Map<String, StreamController<Map<String, dynamic>>> _eventStreams = {};
  final Map<String, Map<String, dynamic>> _latestEvents = {};

  WsConnectionState _state = WsConnectionState.disconnected;
  Completer<void>? _connectCompleter;
  bool _authFailed = false;
  bool _disposed = false;

  // ── public surface ────────────────────────────────────────────────

  WsConnectionState get state => _state;

  Stream<WsConnectionState> get connectionState => _stateController.stream;

  /// Every `game:error` the server sends, auth failures included.
  Stream<GameError> get errors => _errorController.stream;

  bool get isConnected => _state == WsConnectionState.connected;

  /// Open the socket. Resolves on the first `connect`; rejects with
  /// [WsAuthException] if the server rejects the token. A transport-level
  /// failure (server down) does **not** reject — the transport keeps
  /// retrying and [connectionState] reports `reconnecting` — unless
  /// [timeout] is given, in which case a [TimeoutException] is thrown.
  Future<void> connect({Duration? timeout}) {
    _throwIfDisposed();
    if (_state == WsConnectionState.connected) return Future<void>.value();

    final existing = _connectCompleter;
    if (existing != null && !existing.isCompleted) {
      return timeout == null
          ? existing.future
          : existing.future.timeout(timeout);
    }

    final completer = Completer<void>();
    _connectCompleter = completer;
    _authFailed = false;
    _setState(WsConnectionState.connecting);
    _transport.connect();

    return timeout == null
        ? completer.future
        : completer.future.timeout(timeout);
  }

  /// Close the socket and stop reconnecting. Safe to call repeatedly.
  void disconnect() {
    if (_disposed) return;
    _transport.disconnect();
    _setState(WsConnectionState.disconnected);
  }

  /// Send [data] (a JSON-encodable map, usually) under [event]. Use the
  /// [GameActions] constants for the name.
  void emit(String event, [Object? data]) {
    _throwIfDisposed();
    _transport.emit(event, data ?? const <String, dynamic>{});
  }

  /// Send an event and wait until the server confirms that it handled it.
  ///
  /// Matchmaking uses this so the UI never claims to be searching when the
  /// join packet was lost during a reconnect.
  Future<Map<String, dynamic>> emitWithAck(
    String event, [
    Object? data,
    Duration timeout = const Duration(seconds: 5),
  ]) {
    _throwIfDisposed();
    if (!isConnected) {
      return Future<Map<String, dynamic>>.error(
        StateError('WebSocket is not connected'),
      );
    }

    final completer = Completer<Map<String, dynamic>>();
    _transport.emitWithAck(
      event,
      data ?? const <String, dynamic>{},
      (response) {
        if (completer.isCompleted) return;
        completer.complete(_asMap(response) ?? const <String, dynamic>{});
      },
    );
    return completer.future.timeout(timeout);
  }

  /// The shared broadcast stream for server event [name]. Created on first
  /// call; every later call returns the same stream.
  Stream<Map<String, dynamic>> stream(String name) {
    _throwIfDisposed();
    return _controllerFor(name).stream;
  }

  /// Like [stream], but first replays the most recently received payload.
  ///
  /// Stateful game screens use this because matchmaking can publish the
  /// initial phase, shop and roster before the route transition completes.
  Stream<Map<String, dynamic>> streamLatest(String name) async* {
    _throwIfDisposed();
    final latest = _latestEvents[name];
    if (latest != null) yield Map<String, dynamic>.unmodifiable(latest);
    yield* stream(name);
  }

  /// [stream] mapped through [parse]. A payload that fails to parse throws
  /// inside the listener's zone — parsers here are defensive and return a
  /// best-effort object instead.
  Stream<T> streamAs<T>(String name, T Function(Map<String, dynamic>) parse) =>
      stream(name).map(parse);

  Stream<T> streamAsLatest<T>(
    String name,
    T Function(Map<String, dynamic>) parse,
  ) =>
      streamLatest(name).map(parse);

  /// Low-level: run [handler] for every [event] payload. Prefer [stream]
  /// / [streamAs] in widgets. Returns a subscription the caller cancels.
  StreamSubscription<Map<String, dynamic>> on(
    String event,
    void Function(Map<String, dynamic> data) handler,
  ) =>
      stream(event).listen(handler);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _transport.dispose();
    for (final c in _eventStreams.values) {
      c.close();
    }
    _eventStreams.clear();
    _latestEvents.clear();
    _stateController.close();
    _errorController.close();
    final pending = _connectCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('WsClient disposed before connect'));
    }
  }

  // ── internals ─────────────────────────────────────────────────────

  void _wire() {
    _transport.onConnect(() {
      _authFailed = false;
      _setState(WsConnectionState.connected);
      final c = _connectCompleter;
      if (c != null && !c.isCompleted) c.complete();
    });

    _transport.onDisconnect((_) {
      if (_disposed) return;
      // An auth failure already forced `disconnected`; otherwise the
      // transport is about to retry.
      if (!_authFailed && _state != WsConnectionState.disconnected) {
        _setState(WsConnectionState.reconnecting);
      }
    });

    _transport.onConnectError((error) {
      if (_disposed || _authFailed) return;
      // Keep the connect() future pending — the transport retries. Just
      // reflect that we're not up.
      if (_state == WsConnectionState.connecting) {
        _setState(WsConnectionState.reconnecting);
      }
    });

    _transport.onReconnectAttempt(() {
      if (!_disposed && _state != WsConnectionState.connected) {
        _setState(WsConnectionState.reconnecting);
      }
    });

    // Register every server event before the socket connects. Match creation
    // publishes phase/shop/state in quick succession and the route may not be
    // mounted yet; caching here prevents the first frame from missing them.
    for (final event in GameEvents.all) {
      _controllerFor(event);
    }
  }

  StreamController<Map<String, dynamic>> _controllerFor(String name) {
    return _eventStreams.putIfAbsent(name, () {
      final controller = StreamController<Map<String, dynamic>>.broadcast();
      _transport.on(name, (data) {
        final map = _asMap(data);
        if (map == null) return;
        _latestEvents[name] = Map<String, dynamic>.from(map);
        if (!controller.isClosed) controller.add(map);
        if (name == GameEvents.error) _handleGameError(map);
      });
      return controller;
    });
  }

  void _handleGameError(Map<String, dynamic> map) {
    final err = GameError.fromJson(map);
    if (!_errorController.isClosed) _errorController.add(err);
    if (!err.isAuth) return;

    _authFailed = true;
    final c = _connectCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(WsAuthException(err.code, err.message));
    }
    _transport.disconnect();
    _setState(WsConnectionState.disconnected);
  }

  void _setState(WsConnectionState next) {
    if (_state == next || _disposed) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _throwIfDisposed() {
    if (_disposed) throw StateError('WsClient has been disposed');
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }
}
