import 'package:auto_chess_mobile/features/history/match_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchHistoryEntry.fromJson', () {
    test('maps winner + opponent + duration', () {
      final e = MatchHistoryEntry.fromJson({
        'matchId': 'm1',
        'opponent': {'id': 'u2', 'username': 'bob'},
        'winner': 'self',
        'status': 'finished',
        'rounds': 7,
        'createdAt': '2026-03-07T14:02:00.000Z',
        'duration': 252,
      });
      expect(e.outcome, MatchOutcome.win);
      expect(e.opponentName, 'bob');
      expect(e.rounds, 7);
      expect(e.duration, const Duration(seconds: 252));
    });

    test('null winner → tie, null opponent username tolerated', () {
      final e = MatchHistoryEntry.fromJson({
        'matchId': 'm2',
        'opponent': {'id': 'u3', 'username': null},
        'winner': null,
        'status': 'finished',
        'rounds': 30,
        'createdAt': '2026-03-01T00:00:00.000Z',
        'duration': null,
      });
      expect(e.outcome, MatchOutcome.tie);
      expect(e.opponentName, isNull);
      expect(e.duration, isNull);
    });

    test("'opponent' winner → loss", () {
      final e = MatchHistoryEntry.fromJson({
        'matchId': 'm3',
        'opponent': {'id': 'u4', 'username': 'carol'},
        'winner': 'opponent',
        'status': 'finished',
        'rounds': 5,
        'createdAt': '2026-02-28T18:00:00.000Z',
        'duration': 60,
      });
      expect(e.outcome, MatchOutcome.loss);
    });
  });

  group('MatchDetail.fromJson', () {
    test('derives per-round winner name from a battle_end event', () {
      final d = MatchDetail.fromJson({
        'matchId': 'm1',
        'players': [
          {'id': 'a', 'username': 'alice'},
          {'id': 'b', 'username': 'bob'},
        ],
        'winner': 'alice',
        'winnerId': 'a',
        'status': 'finished',
        'createdAt': '2026-03-07T14:02:00.000Z',
        'finishedAt': '2026-03-07T14:06:12.000Z',
        'rounds': [
          {
            'roundNumber': 2,
            'events': [
              {'type': 'attack'},
              {'type': 'battle_end', 'winner': 'p2'},
            ],
          },
          {
            'roundNumber': 1,
            'events': [
              {'type': 'battle_end', 'winner': 'p1'},
            ],
          },
        ],
      });

      expect(d.rounds.map((r) => r.roundNumber), [1, 2]); // sorted
      expect(d.rounds[0].winnerName, 'alice');
      expect(d.rounds[1].winnerName, 'bob');
      expect(d.rounds[1].eventCount, 2);
      expect(d.duration, const Duration(minutes: 4, seconds: 12));
    });

    test('missing rounds / finishedAt tolerated', () {
      final d = MatchDetail.fromJson({
        'matchId': 'm9',
        'players': [
          {'id': 'a', 'username': 'alice'},
        ],
        'winner': null,
        'status': 'in_progress',
        'createdAt': '2026-03-07T14:02:00.000Z',
        'finishedAt': null,
      });
      expect(d.rounds, isEmpty);
      expect(d.duration, isNull);
      expect(d.winnerName, isNull);
    });
  });
}
