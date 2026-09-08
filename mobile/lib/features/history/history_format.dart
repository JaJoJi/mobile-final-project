import 'match_models.dart';

/// Coarse Thai "time ago" — history rows only need day / hour / minute
/// granularity.
String relativeThai(DateTime when, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(when);
  if (diff.inDays >= 1) return '${diff.inDays} วัน';
  if (diff.inHours >= 1) return '${diff.inHours} ชม.';
  if (diff.inMinutes >= 1) return '${diff.inMinutes} นาที';
  return 'เมื่อสักครู่';
}

/// `4:12`, `1:03:45` — used for match duration.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String outcomeWordThai(MatchOutcome o) => switch (o) {
      MatchOutcome.win => 'ชนะ',
      MatchOutcome.loss => 'แพ้',
      MatchOutcome.tie => 'เสมอ',
    };
