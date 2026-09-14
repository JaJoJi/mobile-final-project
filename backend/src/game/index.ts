/**
 * Combat engine (P0-BE-09) — public surface.
 *
 * The orchestrator (P0-BE-13) imports `runBattle` and the types; nothing
 * else in the backend should reach into the individual files.
 */
export { runBattle } from './engine';
export { makeRng, rngInt } from './seeded-rng';
export { pickTarget } from './targeting';
export { applyDamage } from './damage';
export {
  UNIT_BASE_STATS,
  atkFor,
  spdFor,
  actsOnTick,
  MAX_CYCLES,
  TICKS_PER_CYCLE,
} from './constants';
export * from './types';
