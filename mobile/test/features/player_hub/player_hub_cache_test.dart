import 'dart:convert';

import 'package:auto_chess_mobile/core/api/api_client.dart';
import 'package:auto_chess_mobile/features/history/history_providers.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_cache_state.dart';
import 'package:auto_chess_mobile/features/player_hub/player_hub_refresh_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingAdapter implements HttpClientAdapter {
  int historyRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/match/history')) {
      historyRequests++;
      return ResponseBody.fromString(
        jsonEncode(<Object>[]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  test('history is reused until explicitly invalidated', () async {
    final adapter = _CountingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(matchHistoryProvider.future);
    await container.read(matchHistoryProvider.future);
    expect(adapter.historyRequests, 1);

    container
        .read(playerHubRefreshControllerProvider)
        .invalidate(const {PlayerHubResource.history});
    await container.read(matchHistoryProvider.future);
    expect(adapter.historyRequests, 2);
  });

  test('stale navigation refreshes while fresh navigation reuses cache',
      () async {
    final adapter = _CountingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(matchHistoryProvider.future);
    final refresh = container.read(playerHubRefreshControllerProvider);
    refresh.refreshIfStale(const {PlayerHubResource.history});
    await container.read(matchHistoryProvider.future);
    expect(adapter.historyRequests, 1);

    container.read(playerHubFreshnessProvider.notifier).markFresh(
          PlayerHubResource.history,
          DateTime.now().subtract(playerHubCacheTtl),
        );
    refresh.refreshIfStale(const {PlayerHubResource.history});
    await container.read(matchHistoryProvider.future);
    expect(adapter.historyRequests, 2);
  });
}
