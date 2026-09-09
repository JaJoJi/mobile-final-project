import 'package:auto_chess_mobile/core/ws/ws_transport.dart';

/// In-memory [WsTransport] that lets a test act as the server: call
/// [serverConnect] / [serverDisconnect] / [emitFromServer] to drive the
/// [WsClient] under test, and read [sent] to assert what the client sent.
class FakeWsTransport implements WsTransport {
  final List<({String event, Object? data})> sent = [];
  final List<String> offCalls = [];

  int connectCalls = 0;
  int disconnectCalls = 0;
  bool disposed = false;
  bool _connected = false;

  void Function()? _onConnect;
  void Function(dynamic reason)? _onDisconnect;
  void Function(dynamic error)? _onConnectError;
  void Function()? _onReconnectAttempt;
  final Map<String, void Function(dynamic data)> _handlers = {};

  // ── driven by the test (acting as the server) ─────────────────────

  void serverConnect() {
    _connected = true;
    _onConnect?.call();
  }

  void serverDisconnect([String reason = 'io server disconnect']) {
    _connected = false;
    _onDisconnect?.call(reason);
  }

  void serverConnectError([Object? error = 'xhr poll error']) =>
      _onConnectError?.call(error);

  void serverReconnectAttempt() => _onReconnectAttempt?.call();

  void emitFromServer(String event, Object? data) =>
      _handlers[event]?.call(data);

  bool hasHandlerFor(String event) => _handlers.containsKey(event);

  // ── WsTransport ──────────────────────────────────────────────────

  @override
  bool get connected => _connected;

  @override
  void connect() => connectCalls++;

  @override
  void disconnect() {
    disconnectCalls++;
    _connected = false;
  }

  @override
  void dispose() => disposed = true;

  @override
  void emit(String event, Object? data) => sent.add((event: event, data: data));

  @override
  void on(String event, void Function(dynamic data) handler) =>
      _handlers[event] = handler;

  @override
  void off(String event) {
    offCalls.add(event);
    _handlers.remove(event);
  }

  @override
  void onConnect(void Function() handler) => _onConnect = handler;

  @override
  void onDisconnect(void Function(dynamic reason) handler) =>
      _onDisconnect = handler;

  @override
  void onConnectError(void Function(dynamic error) handler) =>
      _onConnectError = handler;

  @override
  void onReconnectAttempt(void Function() handler) =>
      _onReconnectAttempt = handler;
}
