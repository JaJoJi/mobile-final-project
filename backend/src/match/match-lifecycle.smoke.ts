/**
 * Dependency-light smoke test for P0-BE-12.
 * Run after build: `npm run smoke:match-lifecycle`.
 */
import { ForbiddenException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { randomUUID } from 'crypto';
import { MatchDetailDto } from './dto/match-detail.dto';
import { MatchHistoryDto } from './dto/match-history.dto';
import { MatchRound } from './match-round.entity';
import { Match } from './match.entity';
import { MatchService } from './match.service';

interface Result {
  name: string;
  passed: boolean;
  detail: string;
}

function makeMatch(overrides: Partial<Match> = {}): Match {
  return {
    id: randomUUID(),
    player1Id: randomUUID(),
    player2Id: randomUUID(),
    winnerId: null,
    status: 'in_progress',
    matchSeed: randomUUID(),
    wipeIndexP1: 0,
    wipeIndexP2: 0,
    p1State: { hp: 100, gold: 5, board: [], bench: [] },
    p2State: { hp: 75, gold: 3, board: [], bench: [] },
    createdAt: new Date(Date.now() - 90_000),
    finishedAt: null,
    ...overrides,
  };
}

class FakeMatchRepository {
  readonly rows = new Map<string, Match>();
  readonly rounds = new Map<string, MatchRound[]>();

  async findById(id: string): Promise<Match | null> {
    return this.rows.get(id) ?? null;
  }

  async findByIdForUpdate(id: string): Promise<Match | null> {
    return this.findById(id);
  }

  async findActiveByUserId(userId: string): Promise<Match | null> {
    return [...this.rows.values()].find(
      (match) =>
        match.status === 'in_progress' &&
        (match.player1Id === userId || match.player2Id === userId),
    ) ?? null;
  }

  async updateState(
    matchId: string,
    side: 'p1' | 'p2',
    state: Record<string, unknown>,
  ): Promise<boolean> {
    const match = this.rows.get(matchId);
    if (!match) return false;
    match[side === 'p1' ? 'p1State' : 'p2State'] = state;
    return true;
  }

  async saveRoundEvents(
    matchId: string,
    roundNumber: number,
    events: Record<string, unknown>[],
  ): Promise<MatchRound> {
    const rows = this.rounds.get(matchId) ?? [];
    let round = rows.find((item) => item.roundNumber === roundNumber);
    if (!round) {
      round = {
        id: randomUUID(),
        matchId,
        roundNumber,
        events,
        createdAt: new Date(),
      };
      rows.push(round);
      this.rounds.set(matchId, rows);
    } else {
      round.events = events;
    }
    return round;
  }

  async findRounds(matchId: string): Promise<MatchRound[]> {
    return [...(this.rounds.get(matchId) ?? [])].sort(
      (a, b) => a.roundNumber - b.roundNumber,
    );
  }

  async findHistoryByUserId(userId: string, limit: number): Promise<Match[]> {
    return [...this.rows.values()]
      .filter(
        (match) =>
          match.status !== 'in_progress' &&
          (match.player1Id === userId || match.player2Id === userId),
      )
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .slice(0, limit);
  }

  async countRoundsByMatchIds(ids: string[]): Promise<Map<string, number>> {
    return new Map(ids.map((id) => [id, this.rounds.get(id)?.length ?? 0]));
  }

  async finalize(
    match: Match,
    input: { status: Match['status']; winnerId: string | null; finishedAt: Date },
  ): Promise<void> {
    Object.assign(match, input);
  }
}

interface FakeUser {
  id: string;
  username: string;
  rating: number;
}

class FakeUserService {
  readonly rows = new Map<string, FakeUser>();

  async findByIds(ids: string[]): Promise<FakeUser[]> {
    return ids.flatMap((id) => (this.rows.has(id) ? [this.rows.get(id)!] : []));
  }

  async findByIdsForUpdate(ids: string[]): Promise<FakeUser[]> {
    return this.findByIds(ids);
  }

  async updateRating(id: string, delta: number): Promise<void> {
    const user = this.rows.get(id);
    if (!user) throw new Error('user missing');
    user.rating = Math.max(0, user.rating + delta);
  }
}

class FakePubsubBridge {
  readonly events: Array<{ matchId: string; type: string; payload: any }> = [];

  async publish(matchId: string, type: string, payload: unknown): Promise<void> {
    this.events.push({ matchId, type, payload });
  }
}

class FakeDataSource {
  async transaction<T>(work: (manager: object) => Promise<T>): Promise<T> {
    return work({});
  }
}

function add(results: Result[], name: string, passed: boolean, detail: string): void {
  results.push({ name, passed, detail });
}

async function run(): Promise<void> {
  const matches = new FakeMatchRepository();
  const users = new FakeUserService();
  const pubsub = new FakePubsubBridge();
  const service = new MatchService(
    new FakeDataSource() as any,
    matches as any,
    pubsub as any,
    users as any,
  );
  const results: Result[] = [];

  const match = makeMatch();
  matches.rows.set(match.id, match);
  users.rows.set(match.player1Id, { id: match.player1Id, username: 'alice', rating: 1000 });
  users.rows.set(match.player2Id, { id: match.player2Id, username: 'bob', rating: 1000 });

  await service.updateState(match.id, 'p1', { hp: 88, gold: 7 });
  add(
    results,
    'updateState persists the selected player snapshot',
    match.p1State.hp === 88 && match.p2State.hp === 75,
    `p1Hp=${match.p1State.hp} p2Hp=${match.p2State.hp}`,
  );

  await service.appendRoundEvents(match.id, 1, [{ type: 'battle_end', winner: 'p1' }]);
  await service.appendRoundEvents(match.id, 1, [{ type: 'battle_end', winner: 'p2' }]);
  add(
    results,
    'round retry updates one replay row instead of duplicating it',
    matches.rounds.get(match.id)?.length === 1 &&
      matches.rounds.get(match.id)?.[0].events[0].winner === 'p2',
    `rows=${matches.rounds.get(match.id)?.length}`,
  );

  const finalized = await service.finalize(match.id, match.player1Id, 'hp_zero');
  add(
    results,
    'finalize persists winner and applies equal-rating ELO once',
    finalized &&
      match.status === 'finished' &&
      users.rows.get(match.player1Id)?.rating === 1016 &&
      users.rows.get(match.player2Id)?.rating === 984,
    `status=${match.status} p1=${users.rows.get(match.player1Id)?.rating} p2=${users.rows.get(match.player2Id)?.rating}`,
  );
  add(
    results,
    'finalize publishes game:match:end with final state',
    pubsub.events[0]?.type === 'game:match:end' &&
      pubsub.events[0].payload.reason === 'hp_zero' &&
      pubsub.events[0].payload.final.p1.hp === 88,
    JSON.stringify(pubsub.events[0]?.payload),
  );

  const duplicate = await service.finalize(match.id, match.player1Id, 'hp_zero');
  add(
    results,
    'duplicate finalize is idempotent',
    !duplicate &&
      users.rows.get(match.player1Id)?.rating === 1016 &&
      pubsub.events.length === 1,
    `result=${duplicate} rating=${users.rows.get(match.player1Id)?.rating} events=${pubsub.events.length}`,
  );

  const disconnectMatch = makeMatch({
    player1Id: match.player1Id,
    player2Id: match.player2Id,
  });
  matches.rows.set(disconnectMatch.id, disconnectMatch);
  const disconnected = await service.leaveMatch(disconnectMatch.player2Id);
  add(
    results,
    'disconnect forfeits the leaver and awards the opponent',
    disconnected &&
      disconnectMatch.status === 'forfeited' &&
      disconnectMatch.winnerId === disconnectMatch.player1Id &&
      pubsub.events.at(-1)?.payload.reason === 'disconnect',
    `status=${disconnectMatch.status} winner=${disconnectMatch.winnerId}`,
  );

  const history = await service.getHistory(match.player1Id);
  add(
    results,
    'history returns outcome, opponent, round count and duration',
    history.length === 2 &&
      history.every((row) => row.opponent.username === 'bob') &&
      history.some((row) => row.rounds === 1) &&
      history.every((row) => row.duration !== null),
    JSON.stringify(history),
  );

  const detail = await service.getDetail(match.id, match.player1Id);
  add(
    results,
    'detail returns participants and ordered replay events',
    detail.players[0].username === 'alice' &&
      detail.players[1].username === 'bob' &&
      detail.rounds.length === 1 &&
      detail.winner === 'alice',
    `players=${detail.players.map((player) => player.username).join(',')} rounds=${detail.rounds.length}`,
  );

  const [historyErrors, detailErrors] = await Promise.all([
    validate(plainToInstance(MatchHistoryDto, history[0])),
    validate(plainToInstance(MatchDetailDto, detail)),
  ]);
  add(
    results,
    'REST responses satisfy their validated DTO shapes',
    historyErrors.length === 0 && detailErrors.length === 0,
    `historyErrors=${historyErrors.length} detailErrors=${detailErrors.length}`,
  );

  let forbidden = false;
  try {
    await service.getDetail(match.id, randomUUID());
  } catch (error: unknown) {
    forbidden = error instanceof ForbiddenException;
  }
  add(
    results,
    'detail rejects users outside the match',
    forbidden,
    `forbidden=${forbidden}`,
  );

  console.log('\n[match lifecycle smoke results]');
  let passed = 0;
  for (const result of results) {
    const tag = result.passed ? 'PASS' : 'FAIL';
    if (result.passed) passed++;
    console.log(`  ${tag}  ${result.name} — ${result.detail}`);
  }
  console.log(`\n[summary] ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exitCode = 1;
}

run().catch((error: unknown) => {
  console.error('[FAIL]', error);
  process.exitCode = 1;
});
