import 'dart:convert';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/auth/auth_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the secure-storage platform channel.
Map<String, String> _installFakeStorage() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return store[args['key']];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key']);
          return null;
        case 'containsKey':
          return store.containsKey(args['key']);
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
      }
      return null;
    },
  );
  return store;
}

/// Dio adapter that answers from [handler] instead of the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> store;

  setUp(() {
    store = _installFakeStorage();
    AuthGate.instance.signalSignedIn(); // start "signed in"
  });

  Dio buildDio(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
    dio.httpClientAdapter = adapter;
    ApiClient(
      dio: dio,
      storage: const FlutterSecureStorage(),
    ); // wires AuthInterceptor
    return dio;
  }

  test('401 → refreshes and retries the original request once', () async {
    store['access_token'] = 'old-access';
    store['refresh_token'] = 'good-refresh';
    store['user_id'] = 'u1';

    var meCalls = 0;
    var refreshCalls = 0;

    final dio = buildDio(
      _FakeAdapter((options) {
        if (options.path == '/auth/refresh') {
          refreshCalls++;
          return _json(
            {
              'userId': 'u1',
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
            200,
          );
        }
        if (options.path == '/user/me') {
          meCalls++;
          final auth = options.headers['Authorization'];
          if (auth == 'Bearer new-access') {
            return _json({'id': 'u1', 'username': 'alice'}, 200);
          }
          return _json({'message': 'unauthorized'}, 401);
        }
        return _json({}, 404);
      }),
    );

    final res = await dio.get<dynamic>('/user/me');

    expect(res.statusCode, 200);
    expect(res.data['username'], 'alice');
    expect(meCalls, 2, reason: 'first 401, then retry');
    expect(refreshCalls, 1);
    expect(store['access_token'], 'new-access');
    expect(store['refresh_token'], 'new-refresh');
    expect(AuthGate.instance.isSignedIn, isTrue);
  });

  test('refresh fails → clears storage, signals sign-out, surfaces the 401',
      () async {
    store['access_token'] = 'old-access';
    store['refresh_token'] = 'dead-refresh';
    store['user_id'] = 'u1';

    final dio = buildDio(
      _FakeAdapter((options) {
        if (options.path == '/auth/refresh') {
          return _json({'message': 'refresh expired'}, 401);
        }
        return _json({'message': 'unauthorized'}, 401);
      }),
    );

    await expectLater(
      dio.get<dynamic>('/user/me'),
      throwsA(
        isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401),
      ),
    );

    expect(store.containsKey('access_token'), isFalse);
    expect(store.containsKey('refresh_token'), isFalse);
    expect(AuthGate.instance.isSignedIn, isFalse);
  });

  test('no retry loop when the retried request also 401s', () async {
    store['access_token'] = 'old-access';
    store['refresh_token'] = 'good-refresh';

    var meCalls = 0;
    final dio = buildDio(
      _FakeAdapter((options) {
        if (options.path == '/auth/refresh') {
          return _json(
            {
              'userId': 'u1',
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
            200,
          );
        }
        meCalls++;
        return _json({'message': 'still no'}, 401);
      }),
    );

    await expectLater(
      dio.get<dynamic>('/user/me'),
      throwsA(isA<DioException>()),
    );
    expect(meCalls, 2, reason: 'original + one retry, no third attempt');
  });

  test('401 on an /auth/ path is not intercepted', () async {
    var refreshCalls = 0;
    final dio = buildDio(
      _FakeAdapter((options) {
        refreshCalls++;
        return _json({'message': 'bad creds'}, 401);
      }),
    );

    await expectLater(
      dio.post<dynamic>('/auth/login', data: {'email': 'x', 'password': 'y'}),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 1, reason: 'login called once, no refresh attempt');
  });
}
