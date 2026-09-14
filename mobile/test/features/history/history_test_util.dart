import 'dart:convert';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/core/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? _,
    Future<void>? __,
  ) async =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void installFakeSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );
}

/// Pump [child] as a single route so `context.push('/history/x')` etc.
/// don't blow up, with the API client faked.
Future<void> pumpHistory(
  WidgetTester tester,
  Widget child,
  FakeAdapter adapter,
) async {
  installFakeSecureStorage();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = adapter;

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(path: '/history/:id', builder: (_, __) => const _Stub('detail')),
      GoRoute(path: '/lobby', builder: (_, __) => const _Stub('lobby')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(ApiClient(dio: dio))],
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.tag);
  final String tag;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:$tag')));
}
