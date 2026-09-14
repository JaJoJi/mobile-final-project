/// Transport seam under [WsClient].
///
/// [WsClient] talks to this interface, never to `socket_io_client`
/// directly, so tests can drive the client with a fake socket (see
/// `test/core/ws/fake_ws_transport.dart`). Production uses
/// [SocketIoTransport].
library;

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Returns the current access token (or `null` if signed out). Called on
/// every (re)connect so a token refreshed while offline is picked up.
typedef WsTokenProvider = Future<String?> Function();

abstract class WsTransport {
  /// Open the connection (or start the reconnect loop).
  void connect();

  /// Close the connection and stop reconnecting.
  void disconnect();

  /// Release all resources. The transport is unusable afterwards.
  void dispose();

  /// Send [data] under [event].
  void emit(String event, Object? data);

  /// Send [data] and invoke [ack] with the server acknowledgement.
  void emitWithAck(
    String event,
    Object? data,
    void Function(dynamic response) ack,
  );

  /// Register [handler] for server-sent [event]. At most one handler per
  /// event name (a second call replaces the first).
  void on(String event, void Function(dynamic data) handler);

  /// Drop the handler for [event].
  void off(String event);

  bool get connected;

  // ── lifecycle callbacks (each replaces the previous) ──────────────
  void onConnect(void Function() handler);
  void onDisconnect(void Function(dynamic reason) handler);

  /// Fired on a failed connection attempt (server unreachable, handshake
  /// rejected, …). socket.io keeps retrying afterwards.
  void onConnectError(void Function(dynamic error) handler);

  /// Fired each time the manager starts another reconnect attempt.
  void onReconnectAttempt(void Function() handler);
}

/// Real transport: a `socket_io_client` socket on the `/game` namespace
/// with JWT auth in the handshake and exponential-backoff reconnect
/// (1s → 30s cap) handled by the socket.io manager.
class SocketIoTransport implements WsTransport {
  SocketIoTransport({
    required String baseUrl,
    required WsTokenProvider tokenProvider,
  }) : _socket = io.io(
          _gameNamespaceUri(baseUrl),
          io.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .enableReconnection()
              .setReconnectionAttempts(double.infinity)
              .setReconnectionDelay(1000)
              .setReconnectionDelayMax(30000)
              .setRandomizationFactor(0.5)
              .setAuthFn((cb) async {
                final token = await tokenProvider();
                cb({'token': token ?? ''});
              })
              .build(),
        );

  final io.Socket _socket;

  /// `ws://host` / `http://host[:port]` → `<host>/game`. socket.io parses
  /// the path segment as the namespace.
  static String _gameNamespaceUri(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$trimmed/game';
  }

  @override
  bool get connected => _socket.connected;

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() {
    _socket
      ..clearListeners()
      ..dispose();
  }

  @override
  void emit(String event, Object? data) => _socket.emit(event, data);

  @override
  void emitWithAck(
    String event,
    Object? data,
    void Function(dynamic response) ack,
  ) =>
      _socket.emitWithAck(event, data, ack: ack);

  @override
  void on(String event, void Function(dynamic data) handler) {
    _socket
      ..off(event)
      ..on(event, handler);
  }

  @override
  void off(String event) => _socket.off(event);

  @override
  void onConnect(void Function() handler) {
    _socket
      ..off('connect')
      ..onConnect((_) => handler());
  }

  @override
  void onDisconnect(void Function(dynamic reason) handler) {
    _socket
      ..off('disconnect')
      ..onDisconnect(handler);
  }

  @override
  void onConnectError(void Function(dynamic error) handler) {
    _socket
      ..off('connect_error')
      ..onConnectError(handler);
  }

  @override
  void onReconnectAttempt(void Function() handler) {
    _socket.onReconnectAttempt((_) => handler());
  }
}
