import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import type { Match } from '../match/match.entity';
import { MatchService } from '../match/match.service';
import { QueueService } from '../queue/queue.service';
import { RedisService } from '../redis/redis.service';
import { CombatCoordinator } from './combat.coordinator';
import {
  MatchRuntimeState,
  RuntimePlayerState,
  combatDoneKey,
  initialRuntimeHash,
  parseRuntimeHash,
  runtimeKey,
} from './match.runtime-state';
import { PubsubBridge } from './pubsub.bridge';

const SHOP_PHASE_SECONDS = 40;
const SHOP_PHASE_MS = SHOP_PHASE_SECONDS * 1000;
const RUNTIME_TTL_SECONDS = 30 * 60;
const ROUND_GOLD = 5;
const TIE_DAMAGE = 5;

type BattleWinner = 'p1' | 'p2' | null;

@Injectable()
export class MatchRuntimeAdapter {
  private readonly logger = new Logger(MatchRuntimeAdapter.name);

  constructor(
    private readonly redis: RedisService,
    private readonly matches: MatchService,
    private readonly queue: QueueService,
    private readonly pubsub: PubsubBridge,
    private readonly combat: CombatCoordinator,
  ) {}

  /** Creates the shared Redis runtime and starts round one's 40 s timer. */
  async initializeMatch(match: Match): Promise<void> {
    const key = runtimeKey(match.id);
    await this.redis.client.hset(key, initialRuntimeHash(match));
    await this.redis.client.expire(key, RUNTIME_TTL_SECONDS);
    await this.queue.schedulePhaseStart(match.id, 1, SHOP_PHASE_MS);
    await this.pubsub.publish(match.id, 'game:match:phase', this.phasePayload({
      matchId: match.id,
      player1Id: match.player1Id,
      player2Id: match.player2Id,
      matchSeed: match.matchSeed,
      phase: 'shop_place',
      round: 1,
      p1State: initialPlayerState(match.p1State),
      p2State: initialPlayerState(match.p2State),
      readyP1: false,
      readyP2: false,
      wipeIndexP1: match.wipeIndexP1 ?? 0,
      wipeIndexP2: match.wipeIndexP2 ?? 0,
      combatRound: null,
    }, SHOP_PHASE_SECONDS));
  }

  async getRuntime(matchId: string): Promise<MatchRuntimeState> {
    const runtime = await this.findRuntime(matchId);
    if (!runtime) {
      throw new NotFoundException({
        code: 'match.runtime_not_found',
        message: `Runtime for match ${matchId} was not found`,
      });
    }
    return runtime;
  }

  /** Marks one participant ready and starts combat when both flags are set. */
  async markReady(userId: string, matchId: string, round: number): Promise<number> {
    const runtime = await this.requireActionPhase(matchId, round, 'shop_place');
    const side = this.sideFor(runtime, userId);
    await this.redis.client.hset(
      runtimeKey(matchId),
      side === 'p1' ? 'readyP1' : 'readyP2',
      '1',
    );
    const updated = await this.getRuntime(matchId);
    const readyCount = Number(updated.readyP1) + Number(updated.readyP2);
    if (readyCount === 2) await this.tryStartCombat(matchId, round);
    return readyCount;
  }

  /** CAS shop_place → battle; only the winner invokes the combat coordinator. */
  async tryStartCombat(matchId: string, round: number): Promise<boolean> {
    const runtime = await this.findRuntime(matchId);
    if (!runtime) return false;
    if (runtime.phase !== 'shop_place' || runtime.round !== round) return false;
    const instanceId = process.env.HOSTNAME ?? 'nest-local';
    const flipped = await this.redis.eval<number>(
      'phase_flip',
      [runtimeKey(matchId)],
      ['shop_place', 'battle', instanceId, round],
    );
    if (Number(flipped) !== 1) return false;

    runtime.phase = 'battle';
    await this.pubsub.publish(
      matchId,
      'game:match:phase',
      this.phasePayload(runtime, 0),
    );
    await this.combat.runCombat(matchId, round);
    return true;
  }

  /** Records an idempotent client ack; the second distinct player advances. */
  async handleCombatDone(userId: string, matchId: string, round: number): Promise<number> {
    const runtime = await this.requireActionPhase(matchId, round, 'battle');
    this.sideFor(runtime, userId);
    const count = await this.redis.eval<number>(
      'combat_done',
      [combatDoneKey(matchId)],
      [userId, Date.now()],
    );
    if (Number(count) >= 2) await this.applyDamageAndAdvance(matchId, round);
    return Number(count);
  }

  /** Stops the Redis runtime before finalizing a disconnect forfeit. */
  async handleDisconnect(matchId: string, userId: string): Promise<boolean> {
    const runtime = await this.findRuntime(matchId);
    if (!runtime) {
      return this.matches.forfeitDisconnectedPlayer(matchId, userId);
    }
    this.sideFor(runtime, userId);
    if (runtime.phase === 'finished') return false;
    const flipped = await this.redis.eval<number>(
      'phase_flip',
      [runtimeKey(matchId)],
      [runtime.phase, 'finished', process.env.HOSTNAME ?? 'nest-local', runtime.round],
    );
    if (Number(flipped) !== 1) return false;
    return this.matches.forfeitDisconnectedPlayer(matchId, userId);
  }

  /** Shared path for the second ack and BullMQ's 60 s timeout. */
  async applyDamageAndAdvance(matchId: string, round: number): Promise<boolean> {
    const runtime = await this.findRuntime(matchId);
    if (!runtime) return false;
    if (
      runtime.phase !== 'battle' ||
      runtime.round !== round ||
      runtime.combatRound !== round
    ) return false;

    const events = await this.pubsub.getCombatResult(matchId);
    if (!events) return false;
    const winner = this.battleWinner(events as unknown as Record<string, unknown>[]);
    const flipped = await this.redis.eval<number>(
      'phase_flip',
      [runtimeKey(matchId)],
      ['battle', 'resolved', process.env.HOSTNAME ?? 'nest-local', round],
    );
    if (Number(flipped) !== 1) return false;

    const p1 = { ...runtime.p1State };
    const p2 = { ...runtime.p2State };
    const hpBefore = { p1: p1.hp, p2: p2.hp };
    const damage = this.damageFor(winner, runtime.wipeIndexP1, runtime.wipeIndexP2);
    runtime.wipeIndexP1 = damage.wipeIndexP1;
    runtime.wipeIndexP2 = damage.wipeIndexP2;
    p1.hp = Math.max(0, p1.hp - damage.p1);
    p2.hp = Math.max(0, p2.hp - damage.p2);

    const damagePayload = {
      matchId,
      round,
      damage: {
        p1: {
          wiped: winner === 'p2',
          tie: winner === null,
          hpBefore: hpBefore.p1,
          hpAfter: p1.hp,
          damageApplied: damage.p1,
        },
        p2: {
          wiped: winner === 'p1',
          tie: winner === null,
          hpBefore: hpBefore.p2,
          hpAfter: p2.hp,
          damageApplied: damage.p2,
        },
      },
      winner: winner ?? 'tie',
    };

    const winnerId = p1.hp <= 0 && p2.hp <= 0
      ? null
      : p1.hp <= 0
        ? runtime.player2Id
        : p2.hp <= 0
          ? runtime.player1Id
          : undefined;

    if (winnerId !== undefined) {
      await this.persistSnapshot(runtime, p1, p2);
      await this.redis.client.hset(runtimeKey(matchId), {
        phase: 'finished',
        p1State: JSON.stringify(p1),
        p2State: JSON.stringify(p2),
        wipeIndexP1: String(runtime.wipeIndexP1),
        wipeIndexP2: String(runtime.wipeIndexP2),
      });
      await this.pubsub.publish(matchId, 'game:match:damage', damagePayload);
      await this.matches.finalize(matchId, winnerId, 'hp_zero');
      return true;
    }

    p1.gold += ROUND_GOLD;
    p2.gold += ROUND_GOLD;
    p1.ready = false;
    p2.ready = false;
    const nextRound = round + 1;
    await this.persistSnapshot(runtime, p1, p2);
    await this.redis.client.hset(runtimeKey(matchId), {
      round: String(nextRound),
      p1State: JSON.stringify(p1),
      p2State: JSON.stringify(p2),
      readyP1: '0',
      readyP2: '0',
      wipeIndexP1: String(runtime.wipeIndexP1),
      wipeIndexP2: String(runtime.wipeIndexP2),
      combatRound: '',
    });
    const nextFlipped = await this.redis.eval<number>(
      'phase_flip',
      [runtimeKey(matchId)],
      ['resolved', 'shop_place', process.env.HOSTNAME ?? 'nest-local', nextRound],
    );
    if (Number(nextFlipped) !== 1) {
      throw new Error(`match.phase_advance_failed: ${matchId} round ${round}`);
    }

    runtime.phase = 'shop_place';
    runtime.round = nextRound;
    runtime.p1State = p1;
    runtime.p2State = p2;
    runtime.readyP1 = false;
    runtime.readyP2 = false;
    runtime.combatRound = null;
    await this.redis.client.expire(runtimeKey(matchId), RUNTIME_TTL_SECONDS);
    await this.queue.schedulePhaseStart(matchId, nextRound, SHOP_PHASE_MS);
    await this.pubsub.publish(matchId, 'game:match:damage', damagePayload);
    await this.pubsub.publish(
      matchId,
      'game:match:phase',
      this.phasePayload(runtime, SHOP_PHASE_SECONDS),
    );
    this.logger.log(`advanced match=${matchId} round=${round} -> ${nextRound}`);
    return true;
  }

  private async requireActionPhase(
    matchId: string,
    round: number,
    phase: 'shop_place' | 'battle',
  ): Promise<MatchRuntimeState> {
    const runtime = await this.getRuntime(matchId);
    if (runtime.round !== round) {
      throw new BadRequestException({
        code: 'match.round_mismatch',
        message: `Expected round ${runtime.round}, received ${round}`,
      });
    }
    if (runtime.phase !== phase) {
      throw new BadRequestException({
        code: 'match.not_your_turn',
        message: `Action requires ${phase}; current phase is ${runtime.phase}`,
      });
    }
    return runtime;
  }

  private async findRuntime(matchId: string): Promise<MatchRuntimeState | null> {
    return parseRuntimeHash(
      matchId,
      await this.redis.client.hgetall(runtimeKey(matchId)),
    );
  }

  private sideFor(runtime: MatchRuntimeState, userId: string): 'p1' | 'p2' {
    if (runtime.player1Id === userId) return 'p1';
    if (runtime.player2Id === userId) return 'p2';
    throw new BadRequestException({
      code: 'match.not_participant',
      message: 'User is not a participant in this match',
    });
  }

  private battleWinner(events: Record<string, unknown>[]): BattleWinner {
    const end = [...events].reverse().find((event) => event.type === 'battle_end');
    if (!end || (end.winner !== 'p1' && end.winner !== 'p2' && end.winner !== null)) {
      throw new Error('combat.internal: battle_end event missing or invalid');
    }
    return end.winner as BattleWinner;
  }

  private damageFor(winner: BattleWinner, p1Index: number, p2Index: number) {
    if (winner === null) {
      return { p1: TIE_DAMAGE, p2: TIE_DAMAGE, wipeIndexP1: p1Index, wipeIndexP2: p2Index };
    }
    if (winner === 'p1') {
      const next = Math.min(5, p2Index + 1);
      return { p1: 0, p2: next * 5, wipeIndexP1: p1Index, wipeIndexP2: next };
    }
    const next = Math.min(5, p1Index + 1);
    return { p1: next * 5, p2: 0, wipeIndexP1: next, wipeIndexP2: p2Index };
  }

  private persistSnapshot(
    runtime: MatchRuntimeState,
    p1State: RuntimePlayerState,
    p2State: RuntimePlayerState,
  ): Promise<void> {
    return this.matches.updateRuntimeSnapshot(runtime.matchId, {
      p1State,
      p2State,
      wipeIndexP1: runtime.wipeIndexP1,
      wipeIndexP2: runtime.wipeIndexP2,
    });
  }

  private phasePayload(runtime: MatchRuntimeState, timer: number) {
    return {
      matchId: runtime.matchId,
      phase: runtime.phase,
      round: runtime.round,
      timer,
      players: [
        {
          id: runtime.player1Id,
          hp: runtime.p1State.hp,
          gold: runtime.p1State.gold,
          ready: runtime.readyP1,
        },
        {
          id: runtime.player2Id,
          hp: runtime.p2State.hp,
          gold: runtime.p2State.gold,
          ready: runtime.readyP2,
        },
      ],
    };
  }
}

function initialPlayerState(state: Record<string, unknown>): RuntimePlayerState {
  return {
    ...state,
    hp: typeof state.hp === 'number' ? state.hp : 100,
    gold: typeof state.gold === 'number' ? state.gold : 5,
    ready: false,
    board: Array.isArray(state.board) ? state.board : Array(9).fill(null),
    bench: Array.isArray(state.bench) ? state.bench : Array(8).fill(null),
  } as RuntimePlayerState;
}
