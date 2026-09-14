import {
  COMBAT_DONE_TIMEOUT_MS,
  COMBAT_RESULT_TTL_SECONDS,
  combatDoneTimeoutMs,
} from './combat-timing';

describe('combat timing', () => {
  it('keeps the result alive beyond the fallback worker deadline', () => {
    expect(COMBAT_RESULT_TTL_SECONDS * 1000).toBeGreaterThan(
      COMBAT_DONE_TIMEOUT_MS,
    );
    expect(COMBAT_RESULT_TTL_SECONDS * 1000 - COMBAT_DONE_TIMEOUT_MS)
      .toBeGreaterThanOrEqual(10_000);
  });

  it('allows an explicit short local-test timeout', () => {
    expect(combatDoneTimeoutMs('1500')).toBe(1500);
  });

  it('uses the real playback budget for missing or invalid configuration', () => {
    expect(combatDoneTimeoutMs(undefined)).toBe(60_000);
    expect(combatDoneTimeoutMs('fast')).toBe(60_000);
    expect(combatDoneTimeoutMs('100')).toBe(60_000);
  });
});
