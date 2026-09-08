/**
 * Smoke harness for P0-BE-07 (Match + MatchRound entities + CreateMatches migration).
 *
 * Verifies the entities round-trip through Postgres via MatchRepository:
 *
 *   1. MatchRepository.create() inserts a row with all 9 required columns
 *   2. findById returns it with defaults: status='in_progress', wipeIndex*=0
 *   3. findActiveByUserId(player1Id) returns it
 *   4. findActiveByUserId(nonExistent) returns null
 *   5. match_rounds row inserts and ON DELETE CASCADE works (delete
 *      match → round vanishes)
 *
 * Run inside the docker network:
 *   docker compose exec nest-1 node dist/match/match.smoke.js
 * The script talks to Postgres directly using a DataSource mirroring
 * `backend/src/data-source.ts` so it doesn't need a running Nest app.
 */
import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { v4 as uuidv4 } from 'uuid';
import { ENTITIES } from '../database/entities';
import { Match } from './match.entity';
import { MatchRepository } from './match.repository';

interface TestResult {
  name: string;
  passed: boolean;
  detail: string;
}

const DATABASE_URL =
  process.env.DATABASE_URL ?? 'postgres://postgres:postgres@postgres-primary:5432/auto_chess';

async function run(): Promise<void> {
  const ds = new DataSource({
    type: 'postgres',
    url: DATABASE_URL,
    entities: ENTITIES,
    synchronize: false,
    logging: ['error'],
  });
  await ds.initialize();
  console.log(`[connect] ${DATABASE_URL}`);

  const matchRepo = new MatchRepository(
    ds.getRepository(Match),
    ds.getRepository('MatchRound'),
  );

  const results: TestResult[] = [];

  // Use throwaway userIds — we don't FK to users so any uuid works.
  const player1Id = uuidv4();
  const player2Id = uuidv4();
  const matchSeed = uuidv4();

  // 1. create
  let matchId: string;
  try {
    const match = await matchRepo.create({
      player1Id,
      player2Id,
      matchSeed,
      p1State: { hp: 100, gold: 5, roster: [], bench: [] },
      p2State: { hp: 100, gold: 5, roster: [], bench: [] },
    });
    matchId = match.id;
    const ok =
      match.id !== undefined &&
      match.player1Id === player1Id &&
      match.player2Id === player2Id &&
      match.winnerId === null &&
      match.status === 'in_progress' &&
      match.wipeIndexP1 === 0 &&
      match.wipeIndexP2 === 0 &&
      match.finishedAt === null &&
      match.createdAt instanceof Date;
    results.push({
      name: '1. create returns full Match with correct defaults',
      passed: ok,
      detail: `id=${match.id} status=${match.status} wipeP1=${match.wipeIndexP1} wipeP2=${match.wipeIndexP2} winner=${match.winnerId} finishedAt=${match.finishedAt}`,
    });
  } catch (e) {
    console.error('[FAIL] create threw:', e);
    process.exit(1);
  }

  // 2. findById
  {
    const got = await matchRepo.findById(matchId);
    const ok =
      got !== null &&
      got.id === matchId &&
      got.matchSeed === matchSeed &&
      got.p1State.hp === 100;
    results.push({
      name: '2. findById returns the row with jsonb snapshot intact',
      passed: ok,
      detail: `got=${got ? `id=${got.id} seed=${got.matchSeed} p1State=${JSON.stringify(got.p1State)}` : 'null'}`,
    });
  }

  // 3. findActiveByUserId (player1)
  {
    const got = await matchRepo.findActiveByUserId(player1Id);
    results.push({
      name: '3. findActiveByUserId(player1Id) returns the match',
      passed: got !== null && got.id === matchId,
      detail: `got=${got ? `id=${got.id}` : 'null'}`,
    });
  }

  // 4. findActiveByUserId (player2)
  {
    const got = await matchRepo.findActiveByUserId(player2Id);
    results.push({
      name: '4. findActiveByUserId(player2Id) returns the match',
      passed: got !== null && got.id === matchId,
      detail: `got=${got ? `id=${got.id}` : 'null'}`,
    });
  }

  // 5. findActiveByUserId (unknown)
  {
    const got = await matchRepo.findActiveByUserId(uuidv4());
    results.push({
      name: '5. findActiveByUserId(unknown) returns null',
      passed: got === null,
      detail: `got=${got === null ? 'null' : `unexpected ${got.id}`}`,
    });
  }

  // 6. match_rounds insert + ON DELETE CASCADE
  {
    const roundsRepo = ds.getRepository('MatchRound');
    const round = await roundsRepo.save(
      roundsRepo.create({
        matchId,
        roundNumber: 1,
        events: [
          { type: 'attack', cycle: 1, tick: 1, attacker: 'u1', target: 'u2', damage: 10, targetHpAfter: 90 },
          { type: 'death', cycle: 1, tick: 4, unit: 'u2' },
        ],
      }),
    );
    const beforeCount = await roundsRepo.count({ where: { matchId } });
    // delete the parent → FK CASCADE should delete the round too
    await ds.getRepository(Match).delete({ id: matchId });
    const afterCount = await roundsRepo.count({ where: { matchId } });
    results.push({
      name: '6. FK ON DELETE CASCADE removes match_rounds on match delete',
      passed: beforeCount === 1 && afterCount === 0,
      detail: `inserted round=${round.id} before=${beforeCount} after=${afterCount}`,
    });
  }

  await ds.destroy();

  console.log('\n[results]');
  let pass = 0;
  for (const r of results) {
    const tag = r.passed ? 'PASS' : 'FAIL';
    if (r.passed) pass++;
    console.log(`  ${tag}  ${r.name.padEnd(58)} ${r.detail}`);
  }
  console.log(`\n[summary] ${pass}/${results.length} passed`);

  if (pass !== results.length) process.exit(1);
}

run().catch((e: unknown) => {
  console.error('[FAIL]', e);
  process.exit(1);
});
