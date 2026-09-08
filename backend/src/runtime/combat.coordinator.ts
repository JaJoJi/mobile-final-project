import { Inject, Injectable, Logger } from '@nestjs/common';
import { createHash, randomUUID } from 'crypto';
import { MatchService } from '../match/match.service';
import { QueueService } from '../queue/queue.service';
import { RedisService } from '../redis/redis.service';
import { PubsubBridge } from './pubsub.bridge';
import { RUN_BATTLE, RunBattle } from './combat-engine.provider';
import {
  combatDoneKey,
  combatLockKey,
  parseRuntimeHash,
  runtimeKey,
  unitsFromBoard,
} from './match.runtime-state';

const COMBAT_LOCK_TTL_SECONDS = 30;
const COMBAT_DONE_TIMEOUT_MS = 60_000;

@Injectable()
export class CombatCoordinator {
  private readonly logger = new Logger(CombatCoordinator.name);

  constructor(
    private readonly redis: RedisService,
    private readonly pubsub: PubsubBridge,
    private readonly matches: MatchService,
    private readonly queue: QueueService,
    @Inject(RUN_BATTLE) private readonly engine: RunBattle,
  ) {}

  /** Runs one deterministic battle. Redis SET NX makes this safe across replicas. */
  async runCombat(matchId: string, expectedRound: number): Promise<boolean> {
    const lockKey = combatLockKey(matchId);
    const owner = `${process.env.HOSTNAME ?? 'nest-local'}:${randomUUID()}`;
    const acquired = await this.redis.client.set(
      lockKey,
      owner,
      'EX',
      COMBAT_LOCK_TTL_SECONDS,
      'NX',
    );
    if (acquired !== 'OK') return false;

    try {
      const hash = await this.redis.client.hgetall(runtimeKey(matchId));
      const runtime = parseRuntimeHash(matchId, hash);
      if (
        !runtime ||
        runtime.phase !== 'battle' ||
        runtime.round !== expectedRound ||
        runtime.combatRound === expectedRound
      ) {
        return false;
      }

      // Remove the previous round's short-lived replay/ack state before running.
      await this.redis.client.del(combatDoneKey(matchId), `match:${matchId}:combat-result`);
      const events = this.engine({
        p1Units: unitsFromBoard(runtime.p1State.board, 'p1'),
        p2Units: unitsFromBoard(runtime.p2State.board, 'p2'),
        matchSeed: runtime.matchSeed,
        roundSeed: this.roundSeed(runtime.matchSeed, runtime.round),
      });
      const current = parseRuntimeHash(
        matchId,
        await this.redis.client.hgetall(runtimeKey(matchId)),
      );
      if (!current || current.phase !== 'battle' || current.round !== expectedRound) {
        return false;
      }
      const battleEnd = events.at(-1);
      const cycleCount = battleEnd?.type === 'battle_end' ? battleEnd.cycle : 0;

      await this.matches.appendRoundEvents(
        matchId,
        runtime.round,
        events as unknown as Record<string, unknown>[],
      );
      await this.pubsub.writeCombatResult(matchId, events);
      await this.redis.client.hset(runtimeKey(matchId), 'combatRound', String(runtime.round));
      await this.pubsub.publish(matchId, 'game:combat:events', {
        matchId,
        round: runtime.round,
        cycleCount,
        endedAt: Date.now(),
        events,
      });
      await this.queue.scheduleCombatDoneTimeout(
        matchId,
        runtime.round,
        COMBAT_DONE_TIMEOUT_MS,
      );
      this.logger.log(
        `combat complete match=${matchId} round=${runtime.round} events=${events.length}`,
      );
      return true;
    } finally {
      await this.releaseOwnedLock(lockKey, owner);
    }
  }

  private roundSeed(matchSeed: string, round: number): number {
    const digest = createHash('sha256').update(`${matchSeed}:${round}`).digest();
    return digest.readUInt32BE(0);
  }

  /** Compare-and-delete prevents an expired owner from deleting a replacement lock. */
  private async releaseOwnedLock(key: string, owner: string): Promise<void> {
    await this.redis.client.eval(
      "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end return 0",
      1,
      key,
      owner,
    );
  }
}
