/**
 * Deterministic PRNG for the combat engine.
 *
 * `docs/05-combat-spec.md §7` — the battle itself consumes NO randomness;
 * the only seeded draw the engine makes is the per-round "init side" for
 * tie-tick resolution (`§6`), seeded by `roundSeed = matchSeed + round`.
 *
 * Mulberry32 — 32-bit state, fast, good enough for a coin flip / small
 * integer ranges. Never `Math.random()` (non-deterministic → un-replayable
 * → cheatable).
 */

/** Returns a generator producing floats in `[0, 1)` from a 32-bit seed. */
export function makeRng(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Inclusive integer in `[min, max]` drawn from `rng`. */
export function rngInt(rng: () => number, min: number, max: number): number {
  return Math.floor(rng() * (max - min + 1)) + min;
}
