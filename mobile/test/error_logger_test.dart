import 'dart:io';

import 'package:auto_chess_mobile/core/error_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('record() never throws even with no documents directory', () async {
    // No path_provider mock installed → getApplicationDocumentsDirectory
    // throws → _resolveFile returns null → _log swallows it.
    await expectLater(
      ErrorLogger.record(Exception('boom'), StackTrace.current),
      completes,
    );
  });

  test('record() writes an entry when a documents dir is available', () async {
    final dir = Directory.systemTemp.createTempSync('errlog');
    addTearDown(() => dir.deleteSync(recursive: true));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          call.method == 'getApplicationDocumentsDirectory' ? dir.path : null,
    );

    await ErrorLogger.record(
      StateError('kaboom'),
      StackTrace.current,
      context: 'unit-test',
    );

    final log = File('${dir.path}/auto_chess_errors.log');
    expect(log.existsSync(), isTrue);
    final body = log.readAsStringSync();
    expect(body, contains('[unit-test] Bad state: kaboom'));
    expect(body, contains('---'));
  });

  test('init() installs the global handlers', () {
    ErrorLogger.init();
    expect(FlutterError.onError, isNotNull);
    expect(PlatformDispatcher.instance.onError, isNotNull);
  });
}
