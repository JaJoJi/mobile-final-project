import { UNIT_BASE_STATS } from '../game';
import type { Side, Star, UnitId, UnitInstance } from '../game';
import type { Match } from '../match/match.entity';

export type MatchPhase = 'shop_place' | 'battle' | 'resolved' | 'finished';

export interface RuntimeUnitState extends Record<string, unknown> {
  instanceId: string;
  unitId: UnitId;
  star: Star;
  hp: number;
  maxHp: number;
  investedGold?: number;
}

export interface RuntimePlayerState extends Record<string, unknown> {
  hp: number;
  gold: number;
  ready: boolean;
  board: Array<RuntimeUnitState | null>;
  bench: Array<RuntimeUnitState | null>;
}

export interface MatchRuntimeState {
  matchId: string;
  player1Id: string;
  player2Id: string;
  matchSeed: string;
  phase: MatchPhase;
  round: number;
  p1State: RuntimePlayerState;
  p2State: RuntimePlayerState;
  readyP1: boolean;
  readyP2: boolean;
  wipeIndexP1: number;
  wipeIndexP2: number;
  combatRound: number | null;
}

export const runtimeKey = (matchId: string) => `match:${matchId}:runtime`;
export const combatDoneKey = (matchId: string) => `match:${matchId}:combat-done`;
export const combatLockKey = (matchId: string) => `combat-lock:${matchId}`;

export function initialRuntimeHash(match: Match): Record<string, string> {
  const p1State = normalizePlayerState(match.p1State);
  const p2State = normalizePlayerState(match.p2State);
  p1State.ready = false;
  p2State.ready = false;
  return {
    matchId: match.id,
    player1Id: match.player1Id,
    player2Id: match.player2Id,
    matchSeed: match.matchSeed,
    phase: 'shop_place',
    round: '1',
    p1State: JSON.stringify(p1State),
    p2State: JSON.stringify(p2State),
    readyP1: '0',
    readyP2: '0',
    wipeIndexP1: String(match.wipeIndexP1 ?? 0),
    wipeIndexP2: String(match.wipeIndexP2 ?? 0),
    combatRound: '',
  };
}

export function parseRuntimeHash(
  matchId: string,
  hash: Record<string, string>,
): MatchRuntimeState | null {
  if (!hash.phase) return null;
  const round = positiveInt(hash.round);
  if (!round || !isPhase(hash.phase)) return null;
  try {
    return {
      matchId,
      player1Id: hash.player1Id,
      player2Id: hash.player2Id,
      matchSeed: hash.matchSeed,
      phase: hash.phase,
      round,
      p1State: normalizePlayerState(JSON.parse(hash.p1State)),
      p2State: normalizePlayerState(JSON.parse(hash.p2State)),
      readyP1: hash.readyP1 === '1',
      readyP2: hash.readyP2 === '1',
      wipeIndexP1: nonNegativeInt(hash.wipeIndexP1),
      wipeIndexP2: nonNegativeInt(hash.wipeIndexP2),
      combatRound: positiveInt(hash.combatRound),
    };
  } catch {
    return null;
  }
}

export function normalizePlayerState(value: unknown): RuntimePlayerState {
  const source = isRecord(value) ? value : {};
  return {
    ...source,
    hp: finiteNonNegative(source.hp, 100),
    gold: finiteNonNegative(source.gold, 5),
    ready: source.ready === true,
    board: normalizeSlots(source.board, 9),
    bench: normalizeSlots(source.bench, 8),
  };
}

export function unitsFromBoard(
  board: Array<Record<string, unknown> | null>,
  side: Side,
): UnitInstance[] {
  return board.flatMap((entry, slot) => {
    if (!entry) return [];
    const unitId = entry.unitId;
    const star = entry.star;
    if (!isUnitId(unitId) || !isStar(star)) {
      throw new Error(`runtime.invalid_unit: ${side} slot ${slot}`);
    }
    const maxHp = finitePositive(entry.maxHp, UNIT_BASE_STATS[unitId].hp);
    const hp = Math.min(maxHp, finiteNonNegative(entry.hp, maxHp));
    return [{
      instanceId: typeof entry.instanceId === 'string' ? entry.instanceId : `${side}-${slot}`,
      unitId,
      star,
      hp,
      maxHp,
      slot,
      side,
      alive: hp > 0,
    }];
  });
}

function normalizeSlots(value: unknown, length: number): Array<RuntimeUnitState | null> {
  const input = Array.isArray(value) ? value : [];
  return Array.from(
    { length },
    (_, index) => isRecord(input[index]) ? input[index] as RuntimeUnitState : null,
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isPhase(value: string): value is MatchPhase {
  return ['shop_place', 'battle', 'resolved', 'finished'].includes(value);
}

function isUnitId(value: unknown): value is UnitId {
  return ['fighter', 'healer', 'ranger', 'tank'].includes(String(value));
}

function isStar(value: unknown): value is Star {
  return value === 0 || value === 1 || value === 2;
}

function finiteNonNegative(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : fallback;
}

function finitePositive(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback;
}

function positiveInt(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function nonNegativeInt(value: unknown): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : 0;
}
