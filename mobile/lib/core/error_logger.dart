import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Catches every uncaught error and appends it to a local log file so a
/// crash is never silent (P3-FE-02).
///
/// * `FlutterError.onError`  — framework / build / layout errors.
/// * `PlatformDispatcher.instance.onError` — errors that escape the zone
///   (async gaps, platform callbacks).
///
/// The log lives at `<app documents>/auto_chess_errors.log`, one block per
/// error: an ISO-8601 timestamp, a `[context]` tag, the error, its stack,
/// and a `---` separator. Writes are best-effort — a logging failure must
/// never mask the original error or crash the app.
abstract final class ErrorLogger {
  static const _fileName = 'auto_chess_errors.log';
  static File? _file;

  /// Wire the global handlers. Call once from `main()` before `runApp`.
  static void init() {
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(_log(details.exception, details.stack, context: 'flutter'));
      // Keep the default behaviour (red screen in debug, console dump).
      previousFlutterOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(_log(error, stack, context: 'platform'));
      return true; // handled — don't let it kill the isolate
    };
  }

  /// Resolve the log file lazily; returns null if the platform has no
  /// documents dir (e.g. some test hosts) so callers can no-op.
  static Future<File?> _resolveFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return _file = File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _log(
    Object error,
    StackTrace? stack, {
    required String context,
  }) async {
    final entry = StringBuffer()
      ..writeln(DateTime.now().toIso8601String())
      ..writeln('[$context] $error')
      ..writeln(stack ?? StackTrace.current)
      ..writeln('---');
    try {
      final file = await _resolveFile();
      await file?.writeAsString(
        entry.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Best-effort: swallow so logging can't crash the app.
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ErrorLogger:$context] $error');
    }
  }

  /// Manually record a handled error with a caller-supplied [context].
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String context = 'manual',
  }) =>
      _log(error, stack, context: context);
}
