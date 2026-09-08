-- action_log.lua
-- Idempotent per-action write for the match action log (R7).
-- KEYS[1] = match:<id>:actionLog:<userId>
-- KEYS[2] = match:<id>:runtime (optional shop commit)
-- KEYS[3] = match:<id>:shop:<userId> (optional shop commit)
-- ARGV[1] = clientActionId (UUID)
-- ARGV[2] = epoch ms
-- ARGV[3] = runtime player state field (optional)
-- ARGV[4] = runtime player state JSON (optional)
-- ARGV[5] = shop state JSON (optional)
-- ARGV[6] = shop TTL seconds (optional)
-- ARGV[7] = expected runtime phase (optional)
-- ARGV[8] = expected runtime round (optional)
-- Returns 1 if newly recorded, 0 if duplicate, -1 phase mismatch, -2 round mismatch.
--
-- Spec: docs/03-architecture.md §15.
-- A retry from the same client (same clientActionId) is a no-op — the
-- stored timestamp stays the FIRST action's. EXPIRE is refreshed on every
-- insert; 120 s comfortably outlives the longest expected phase (~90 s).
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then return 0 end
if KEYS[2] and KEYS[3] then
  if redis.call('HGET', KEYS[2], 'round') ~= ARGV[8] then return -2 end
  if redis.call('HGET', KEYS[2], 'phase') ~= ARGV[7] then return -1 end
end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[1], 120)
if KEYS[2] and KEYS[3] then
  redis.call('HSET', KEYS[2], ARGV[3], ARGV[4])
  redis.call('SET', KEYS[3], ARGV[5], 'EX', ARGV[6])
end
return 1
