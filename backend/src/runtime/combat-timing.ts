const REAL_COMBAT_DONE_TIMEOUT_MS = 60_000;
// Keep in sync with mobile's kCombatEventDuration. The client no longer
// compresses dense rounds, so the fallback deadline uses this same rate.
export const COMBAT_EVENT_PLAYBACK_MS = 800;
const COMBAT_PLAYBACK_GRACE_MS = 5_000;

/**
 * Maximum time clients get to finish battle playback and acknowledge it.
 *
 * AI/maintainer note: `COMBAT_DONE_TIMEOUT_MS` is a LOCAL FE04 TEST AID.
 * The committed default remains the real 60 s playback budget. Local `.env`
 * may temporarily lower it while FE05 has no combat replay/`combat_done` ACK.
 * Do not hard-code the short test value here or deploy it to production.
 */
export function combatDoneTimeoutMs(raw = process.env.COMBAT_DONE_TIMEOUT_MS) {
  if (raw == null || raw.trim() === '') return REAL_COMBAT_DONE_TIMEOUT_MS;
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed >= 250 && parsed <= 300_000
    ? parsed
    : REAL_COMBAT_DONE_TIMEOUT_MS;
}

export const COMBAT_DONE_TIMEOUT_MS = combatDoneTimeoutMs();

/**
 * Gives production clients enough time to play every visible event at the
 * fixed UI rate. An explicit environment override remains exact because it is
 * used by local backend tests that intentionally do not run the Flutter replay.
 */
export function combatDoneTimeoutForEventCount(
  eventCount: number,
  configuredTimeoutMs = COMBAT_DONE_TIMEOUT_MS,
) {
  if (configuredTimeoutMs !== REAL_COMBAT_DONE_TIMEOUT_MS) {
    return configuredTimeoutMs;
  }
  const replayMs = Math.max(0, eventCount) * COMBAT_EVENT_PLAYBACK_MS;
  return Math.max(
    REAL_COMBAT_DONE_TIMEOUT_MS,
    replayMs + COMBAT_PLAYBACK_GRACE_MS,
  );
}

export function combatResultTtlSeconds(timeoutMs: number) {
  return Math.ceil(timeoutMs / 1000) + 30;
}

/**
 * The timeout worker still needs the cached combat result after it wakes up.
 * Keep a safety margin so Redis expiry and BullMQ scheduling at the same
 * nominal second cannot race each other.
 */
export const COMBAT_RESULT_TTL_SECONDS = combatResultTtlSeconds(
  COMBAT_DONE_TIMEOUT_MS,
);
