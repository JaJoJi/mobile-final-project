/// Always-on trace of the combat replay pipeline: phase changes, batch
/// delivery, playhead progress, and every path that can end a round.
///
/// Deliberately `print` rather than `dart:developer`'s `log`. Playtesting
/// runs the app as `flutter run -d chrome --release`, and on web in
/// release `developer.log` is compiled down to a no-op — nothing reaches
/// the browser console at all. `print` survives dart2js and lands as a
/// `console.log`, so these lines show up in whichever build is actually
/// being played.
///
/// Timestamps are UTC ISO-8601 to match the `time` field pino writes on
/// the Nest side, so a client trace and `docker logs ac-nest-*` can be
/// read against each other directly.
library;

/// Set `false` to silence the trace without unpicking the call sites.
const bool kCombatTraceEnabled = true;

void combatTrace(String message) {
  if (!kCombatTraceEnabled) return;
  // ignore: avoid_print
  print('[combat ${DateTime.now().toUtc().toIso8601String()}] $message');
}
