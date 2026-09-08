import { BadRequestException, Injectable } from '@nestjs/common';
import { createHash, randomUUID } from 'crypto';
import { UNIT_BASE_STATS } from '../game';
import type { Star, UnitId } from '../game';
import { MatchService } from '../match/match.service';
import { RedisService } from '../redis/redis.service';
import {
  MatchRuntimeState,
  RuntimePlayerState,
  RuntimeUnitState,
  parseRuntimeHash,
  runtimeKey,
} from '../runtime/match.runtime-state';
import { PubsubBridge } from '../runtime/pubsub.bridge';

const SHOP_TTL_SECONDS = 30 * 60;
const ACTION_LOCK_TTL_MS = 5_000;
const ACTION_LOCK_ATTEMPTS = 40;

const UNIT_COST: Record<UnitId, number> = {
  fighter: 1,
  healer: 1,
  ranger: 2,
  tank: 2,
};

const UNIT_POOL: ReadonlyArray<{ unitId: UnitId; ceiling: number }> = [
  { unitId: 'fighter', ceiling: 40 },
  { unitId: 'healer', ceiling: 80 },
  { unitId: 'ranger', ceiling: 95 },
  { unitId: 'tank', ceiling: 100 },
];

export interface ShopOffer {
  offerId: string;
  unitId: UnitId;
  star: 0;
}

interface StoredShop {
  round: number;
  refreshCount: number;
  refreshUsed: boolean;
  offers: Array<ShopOffer | null>;
}

export interface ShopActionResult {
  duplicate: boolean;
}

interface ActionContext {
  runtime: MatchRuntimeState;
  side: 'p1' | 'p2';
  state: RuntimePlayerState;
  shop: StoredShop;
}

@Injectable()
export class ShopService {
  constructor(
    private readonly redis: RedisService,
    private readonly matches: MatchService,
    private readonly pubsub: PubsubBridge,
  ) {}

  /** Pure deterministic offer generation used by replay and distribution tests. */
  generateOffers(
    matchSeed: string,
    round: number,
    playerId: string,
    refreshCount = 0,
  ): ShopOffer[] {
    const seedText = `${matchSeed}:${round}:${refreshCount}:${playerId}`;
    const random = mulberry32(hashString(seedText));
    return Array.from({ length: 5 }, (_, index) => {
      const roll = random() * 100;
      const unitId = UNIT_POOL.find((entry) => roll < entry.ceiling)!.unitId;
      return {
        offerId: deterministicOfferId(seedText, index),
        unitId,
        star: 0 as const,
      };
    });
  }

  /** Creates and privately emits both players' shops at the start of a phase. */
  async rollOffersForMatch(runtime: MatchRuntimeState): Promise<void> {
    await Promise.all([
      this.resetShop(runtime, runtime.player1Id),
      this.resetShop(runtime, runtime.player2Id),
    ]);
  }

  async buy(
    userId: string,
    matchId: string,
    round: number,
    offerIndex: number,
    clientActionId: string,
  ): Promise<ShopActionResult> {
    return this.withAction(userId, matchId, round, clientActionId, async (context) => {
      const offer = context.shop.offers[offerIndex];
      if (!offer) this.fail('shop.offer_unavailable', 'This offer is no longer available');
      const cost = UNIT_COST[offer.unitId];
      if (context.state.gold < cost) {
        this.fail('shop.insufficient_gold', 'Not enough gold for this unit');
      }

      context.state.gold -= cost;
      const bought = this.newUnit(offer.unitId, cost);
      if (!this.autoFuse(context.state, bought)) {
        const slot = context.state.bench.findIndex((entry) => entry === null);
        if (slot < 0) this.fail('shop.roster_full', 'Bench is full');
        context.state.bench[slot] = bought;
      }
      context.shop.offers[offerIndex] = null;
    });
  }

  async sell(
    userId: string,
    matchId: string,
    round: number,
    source: 'board' | 'bench',
    slot: number,
    clientActionId: string,
  ): Promise<ShopActionResult> {
    return this.withAction(userId, matchId, round, clientActionId, async (context) => {
      const roster = context.state[source];
      if (slot < 0 || slot >= roster.length) {
        this.fail('shop.invalid_slot', `Invalid ${source} slot`);
      }
      const unit = roster[slot];
      if (!unit) this.fail('shop.unit_not_found', 'No unit exists in that slot');
      context.state.gold += investedGold(unit);
      roster[slot] = null;
    });
  }

  async refresh(
    userId: string,
    matchId: string,
    round: number,
    clientActionId: string,
  ): Promise<ShopActionResult> {
    return this.withAction(userId, matchId, round, clientActionId, async (context) => {
      if (context.shop.refreshUsed) {
        this.fail('shop.refresh_used', 'The free refresh was already used this phase');
      }
      context.shop.refreshUsed = true;
      context.shop.refreshCount += 1;
      context.shop.offers = this.generateOffers(
        context.runtime.matchSeed,
        round,
        userId,
        context.shop.refreshCount,
      );
      return true;
    });
  }

  async fuse(
    userId: string,
    matchId: string,
    round: number,
    unitId: UnitId,
    clientActionId: string,
  ): Promise<ShopActionResult> {
    return this.withAction(userId, matchId, round, clientActionId, async (context) => {
      const candidates = rosterEntries(context.state)
        .filter((entry) => entry.unit.unitId === unitId && entry.unit.star < 2)
        .sort((a, b) => a.unit.star - b.unit.star);
      const pair = candidates.find((entry, index) =>
        candidates.slice(index + 1).some((other) => other.unit.star === entry.unit.star),
      );
      if (!pair) this.fail('shop.cannot_fuse', 'Two same-star copies are required');
      const second = candidates.find((entry) =>
        entry !== pair && entry.unit.star === pair.unit.star,
      )!;
      this.mergeUnits(pair.unit, second.unit);
      context.state[second.source][second.slot] = null;
    });
  }

  private async withAction(
    userId: string,
    matchId: string,
    round: number,
    clientActionId: string,
    mutate: (context: ActionContext) => Promise<boolean | void>,
  ): Promise<ShopActionResult> {
    const logKey = actionLogKey(matchId, userId);
    if (await this.redis.client.hexists(logKey, clientActionId)) {
      return { duplicate: true };
    }

    const lockKey = `match:${matchId}:shop-lock:${userId}`;
    const owner = randomUUID();
    await this.acquireLock(lockKey, owner);
    try {
      if (await this.redis.client.hexists(logKey, clientActionId)) {
        return { duplicate: true };
      }
      const context = await this.actionContext(userId, matchId, round);
      const emitOffers = Boolean(await mutate(context));
      const recorded = await this.persistAction(context, logKey, clientActionId);
      if (!recorded) return { duplicate: true };
      if (emitOffers) await this.publishOffers(context.runtime, userId, context.shop.offers);
      return { duplicate: false };
    } finally {
      await releaseOwnedLock(this.redis, lockKey, owner);
    }
  }

  private async actionContext(
    userId: string,
    matchId: string,
    expectedRound: number,
  ): Promise<ActionContext> {
    const runtime = parseRuntimeHash(
      matchId,
      await this.redis.client.hgetall(runtimeKey(matchId)),
    );
    if (!runtime) this.fail('match.runtime_not_found', 'Match runtime was not found');
    if (runtime.round !== expectedRound) {
      this.fail('match.round_mismatch', `Expected round ${runtime.round}`);
    }
    if (runtime.phase !== 'shop_place') {
      this.fail('match.not_your_turn', 'Shop actions require the shop_place phase');
    }
    const side = runtime.player1Id === userId
      ? 'p1'
      : runtime.player2Id === userId
        ? 'p2'
        : this.fail('match.not_participant', 'User is not a participant');
    const shop = await this.readShop(matchId, userId);
    if (!shop || shop.round !== expectedRound) {
      this.fail('shop.offers_not_found', 'Shop offers were not found for this round');
    }
    return {
      runtime,
      side,
      state: side === 'p1' ? runtime.p1State : runtime.p2State,
      shop,
    };
  }

  private async persistAction(
    context: ActionContext,
    logKey: string,
    clientActionId: string,
  ): Promise<boolean> {
    const stateField = context.side === 'p1' ? 'p1State' : 'p2State';
    const userId = context.side === 'p1'
      ? context.runtime.player1Id
      : context.runtime.player2Id;
    const recorded = await this.redis.eval<number>(
      'action_log',
      [logKey, runtimeKey(context.runtime.matchId), shopKey(context.runtime.matchId, userId)],
      [
        clientActionId,
        Date.now(),
        stateField,
        JSON.stringify(context.state),
        JSON.stringify(context.shop),
        SHOP_TTL_SECONDS,
        'shop_place',
        context.runtime.round,
      ],
    );
    if (Number(recorded) === -2) {
      this.fail('match.round_mismatch', 'The match advanced before this action committed');
    }
    if (Number(recorded) === -1) {
      this.fail('match.not_your_turn', 'The shop phase ended before this action committed');
    }
    if (Number(recorded) !== 1) return false;
    await this.matches.updateState(context.runtime.matchId, context.side, context.state);
    await this.publishState(context.runtime, context.side, context.state);
    return true;
  }

  private async resetShop(runtime: MatchRuntimeState, playerId: string): Promise<void> {
    const shop: StoredShop = {
      round: runtime.round,
      refreshCount: 0,
      refreshUsed: false,
      offers: this.generateOffers(runtime.matchSeed, runtime.round, playerId),
    };
    await this.redis.client.set(
      shopKey(runtime.matchId, playerId),
      JSON.stringify(shop),
      'EX',
      SHOP_TTL_SECONDS,
    );
    await this.publishOffers(runtime, playerId, shop.offers);
  }

  private publishOffers(
    runtime: MatchRuntimeState,
    playerId: string,
    offers: Array<ShopOffer | null>,
  ): Promise<void> {
    return this.pubsub.publishToUser(
      runtime.matchId,
      playerId,
      'game:shop:offer',
      offerPayload(runtime.matchId, runtime.round, offers),
    );
  }

  private async readShop(matchId: string, userId: string): Promise<StoredShop | null> {
    const raw = await this.redis.client.get(shopKey(matchId, userId));
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw) as StoredShop;
      return Array.isArray(parsed.offers) ? parsed : null;
    } catch {
      return null;
    }
  }

  private newUnit(unitId: UnitId, cost: number): RuntimeUnitState {
    const maxHp = UNIT_BASE_STATS[unitId].hp;
    return {
      instanceId: randomUUID(),
      unitId,
      star: 0,
      hp: maxHp,
      maxHp,
      investedGold: cost,
    };
  }

  private autoFuse(state: RuntimePlayerState, bought: RuntimeUnitState): boolean {
    const existing = rosterEntries(state).find((entry) =>
      entry.unit.unitId === bought.unitId && entry.unit.star === bought.star,
    );
    if (!existing) return false;
    this.mergeUnits(existing.unit, bought);
    this.cascadeFuse(state, existing.unit, existing.source, existing.slot);
    return true;
  }

  private cascadeFuse(
    state: RuntimePlayerState,
    unit: RuntimeUnitState,
    source: 'board' | 'bench',
    slot: number,
  ): void {
    while (unit.star < 2) {
      const next = rosterEntries(state).find((entry) =>
        !(entry.source === source && entry.slot === slot) &&
        entry.unit.unitId === unit.unitId &&
        entry.unit.star === unit.star,
      );
      if (!next) return;
      this.mergeUnits(unit, next.unit);
      state[next.source][next.slot] = null;
    }
  }

  private mergeUnits(target: RuntimeUnitState, consumed: RuntimeUnitState): void {
    const totalInvestedGold = investedGold(target) + investedGold(consumed);
    target.star = (target.star + 1) as Star;
    target.investedGold = totalInvestedGold;
    target.hp = target.maxHp;
  }

  private async publishState(
    runtime: MatchRuntimeState,
    changedSide: 'p1' | 'p2',
    changedState: RuntimePlayerState,
  ): Promise<void> {
    const p1 = changedSide === 'p1' ? changedState : runtime.p1State;
    const p2 = changedSide === 'p2' ? changedState : runtime.p2State;
    const readyCount = Number(runtime.readyP1) + Number(runtime.readyP2);
    await Promise.all([
      this.pubsub.publishToUser(
        runtime.matchId,
        runtime.player1Id,
        'game:match:state',
        statePayload(runtime, 'p1', p1, p2, readyCount),
      ),
      this.pubsub.publishToUser(
        runtime.matchId,
        runtime.player2Id,
        'game:match:state',
        statePayload(runtime, 'p2', p2, p1, readyCount),
      ),
    ]);
  }

  private async acquireLock(key: string, owner: string): Promise<void> {
    for (let attempt = 0; attempt < ACTION_LOCK_ATTEMPTS; attempt += 1) {
      const result = await this.redis.client.set(
        key,
        owner,
        'PX',
        ACTION_LOCK_TTL_MS,
        'NX',
      );
      if (result === 'OK') return;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    this.fail('shop.busy', 'Another shop action is still being processed');
  }

  private fail(code: string, message: string): never {
    throw new BadRequestException({ code, message });
  }
}

function shopKey(matchId: string, userId: string): string {
  return `match:${matchId}:shop:${userId}`;
}

function actionLogKey(matchId: string, userId: string): string {
  return `match:${matchId}:actionLog:${userId}`;
}

function offerPayload(matchId: string, round: number, offers: Array<ShopOffer | null>) {
  return { matchId, round, offers };
}

function rosterEntries(state: RuntimePlayerState): Array<{
  source: 'board' | 'bench';
  slot: number;
  unit: RuntimeUnitState;
}> {
  return (['board', 'bench'] as const).flatMap((source) =>
    state[source].flatMap((unit, slot) => unit ? [{ source, slot, unit }] : []),
  );
}

function investedGold(unit: RuntimeUnitState): number {
  const stored = unit.investedGold;
  if (typeof stored === 'number' && Number.isFinite(stored) && stored >= 0) return stored;
  return UNIT_COST[unit.unitId] * (2 ** unit.star);
}

function statePayload(
  runtime: MatchRuntimeState,
  side: 'p1' | 'p2',
  own: RuntimePlayerState,
  opponent: RuntimePlayerState,
  readyCount: number,
) {
  return {
    matchId: runtime.matchId,
    round: runtime.round,
    yourSide: side,
    roster: {
      board: own.board,
      bench: own.bench,
      gold: own.gold,
      hp: own.hp,
    },
    opponent: {
      gold: opponent.gold,
      hp: opponent.hp,
      boardSummary: opponent.board.map((unit) => unit
        ? { unitId: unit.unitId, star: unit.star }
        : null),
    },
    readyCount,
  };
}

function deterministicOfferId(seed: string, index: number): string {
  const hex = createHash('sha256').update(`${seed}:${index}`).digest('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`;
}

function hashString(value: string): number {
  const digest = createHash('sha256').update(value).digest();
  return digest.readUInt32BE(0);
}

function mulberry32(seed: number): () => number {
  return () => {
    seed |= 0;
    seed = (seed + 0x6D2B79F5) | 0;
    let value = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    value = (value + Math.imul(value ^ (value >>> 7), 61 | value)) ^ value;
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

async function releaseOwnedLock(
  redis: RedisService,
  key: string,
  owner: string,
): Promise<void> {
  await redis.client.eval(
    "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end return 0",
    1,
    key,
    owner,
  );
}
