const REAL_COMBAT_DONE_TIMEOUT_MS = 60_000;

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
 * The timeout worker still needs the cached combat result after it wakes up.
 * Keep a safety margin so Redis expiry and BullMQ scheduling at the same
 * nominal second cannot race each other.
 */
export const COMBAT_RESULT_TTL_SECONDS =
  Math.ceil(COMBAT_DONE_TIMEOUT_MS / 1000) + 30;
