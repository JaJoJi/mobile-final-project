/**
 * Real Postgres + REST integration smoke for P0-BE-12.
 * Run inside the Docker network while nest-1 is up:
 *   docker compose exec -T nest-1 npm run smoke:match-lifecycle:integration
 */
import 'reflect-metadata';
import { randomUUID } from 'crypto';
import { DataSource } from 'typeorm';
import { ENTITIES } from '../database/entities';
import { User } from '../user/user.entity';
import { UserService } from '../user/user.service';
import { MatchRound } from './match-round.entity';
import { Match } from './match.entity';
import { MatchRepository } from './match.repository';
import { MatchService } from './match.service';

interface AuthResponse {
  userId: string;
  accessToken: string;
}

interface Result {
  name: string;
  passed: boolean;
  detail: string;
}

class CapturePubsub {
  readonly events: Array<{ matchId: string; type: string; payload: any }> = [];

  async publish(matchId: string, type: string, payload: unknown): Promise<void> {
    this.events.push({ matchId, type, payload });
  }
}

const HTTP_BASE = process.env.HTTP_BASE ?? 'http://localhost:3000';
const DATABASE_URL =
  process.env.DATABASE_URL ?? 'postgres://postgres:postgres@postgres-primary:5432/auto_chess';

async function request<T>(
  path: string,
  init: RequestInit = {},
): Promise<{ status: number; body: T }> {
  const response = await fetch(`${HTTP_BASE}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
  const body = (await response.json().catch(() => null)) as T;
  return { status: response.status, body };
}

async function register(label: string): Promise<AuthResponse> {
  const suffix = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  const response = await request<AuthResponse>('/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      email: `${label}-${suffix}@test.local`,
      username: `${label}${randomUUID().replaceAll('-', '').slice(0, 10)}`,
      password: 'hunter22-long-enough',
    }),
  });
  if (response.status !== 201) {
    throw new Error(`register ${label} failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body;
}

function auth(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}

function add(results: Result[], name: string, passed: boolean, detail: string): void {
  results.push({ name, passed, detail });
}

async function run(): Promise<void> {
  const ds = new DataSource({
    type: 'postgres',
    url: DATABASE_URL,
    entities: ENTITIES,
    synchronize: false,
    logging: ['error'],
  });
  await ds.initialize();

  const matches = new MatchRepository(
    ds.getRepository(Match),
    ds.getRepository(MatchRound),
  );
  const users = new UserService(ds.getRepository(User));
  const pubsub = new CapturePubsub();
  const service = new MatchService(ds, matches, pubsub as any, users);
  const results: Result[] = [];
  const createdUserIds: string[] = [];
  let matchId: string | null = null;

  try {
    const p1 = await register('lifea');
    const p2 = await register('lifeb');
    const outsider = await register('lifex');
    createdUserIds.push(p1.userId, p2.userId, outsider.userId);

    const match = await matches.create({
      player1Id: p1.userId,
      player2Id: p2.userId,
      matchSeed: randomUUID(),
      p1State: { hp: 100, gold: 5, board: Array(9).fill(null), bench: Array(8).fill(null) },
      p2State: { hp: 100, gold: 5, board: Array(9).fill(null), bench: Array(8).fill(null) },
    });
    matchId = match.id;

    await service.updateState(match.id, 'p1', {
      hp: 82,
      gold: 7,
      board: Array(9).fill(null),
      bench: Array(8).fill(null),
    });
    await service.appendRoundEvents(match.id, 1, [
      { type: 'battle_end', cycle: 4, winner: 'p1' },
    ]);
    await service.appendRoundEvents(match.id, 1, [
      { type: 'battle_end', cycle: 5, winner: 'p1' },
    ]);

    const finalizeResults = await Promise.all([
      service.finalize(match.id, p1.userId, 'hp_zero'),
      service.finalize(match.id, p1.userId, 'hp_zero'),
    ]);
    const p1Me = await request<any>('/user/me', { headers: auth(p1.accessToken) });
    const p2Me = await request<any>('/user/me', { headers: auth(p2.accessToken) });
    add(
      results,
      'concurrent finalize awards ELO exactly once',
      finalizeResults.filter(Boolean).length === 1 &&
        p1Me.body.rating === 1016 &&
        p2Me.body.rating === 984 &&
        pubsub.events.length === 1,
      `finalized=${JSON.stringify(finalizeResults)} ratings=${p1Me.body.rating}/${p2Me.body.rating} events=${pubsub.events.length}`,
    );

    const history = await request<any[]>('/match/history', {
      headers: auth(p1.accessToken),
    });
    add(
      results,
      'GET /match/history returns the authenticated player history',
      history.status === 200 &&
        history.body.length === 1 &&
        history.body[0].matchId === match.id &&
        history.body[0].winner === 'self' &&
        history.body[0].rounds === 1,
      `status=${history.status} body=${JSON.stringify(history.body)}`,
    );

    const detail = await request<any>(`/match/${match.id}`, {
      headers: auth(p2.accessToken),
    });
    add(
      results,
      'GET /match/:id returns participants and one idempotent round',
      detail.status === 200 &&
        detail.body.players.length === 2 &&
        detail.body.rounds.length === 1 &&
        detail.body.rounds[0].events[0].cycle === 5,
      `status=${detail.status} rounds=${detail.body?.rounds?.length}`,
    );

    const forbidden = await request<any>(`/match/${match.id}`, {
      headers: auth(outsider.accessToken),
    });
    add(
      results,
      'GET /match/:id rejects a non-participant',
      forbidden.status === 403 && forbidden.body?.code === 'match.not_your_match',
      `status=${forbidden.status} body=${JSON.stringify(forbidden.body)}`,
    );

    const unauthorized = await request<any>('/match/history');
    add(
      results,
      'match history requires an access JWT',
      unauthorized.status === 401,
      `status=${unauthorized.status}`,
    );

    console.log('\n[match lifecycle integration results]');
    let passed = 0;
    for (const result of results) {
      const tag = result.passed ? 'PASS' : 'FAIL';
      if (result.passed) passed++;
      console.log(`  ${tag}  ${result.name} — ${result.detail}`);
    }
    console.log(`\n[summary] ${passed}/${results.length} passed`);
    if (passed !== results.length) process.exitCode = 1;
  } finally {
    if (matchId) await ds.getRepository(Match).delete({ id: matchId });
    if (createdUserIds.length > 0) await ds.getRepository(User).delete(createdUserIds);
    await ds.destroy();
  }
}

run().catch((error: unknown) => {
  console.error('[FAIL]', error);
  process.exitCode = 1;
});
