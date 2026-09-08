-- action_log.lua
-- Idempotent per-action write for the match action log (R7).
-- KEYS[1] = match:<id>:actionLog:<userId>
-- ARGV[1] = clientActionId (UUID)
-- ARGV[2] = epoch ms
-- Returns 1 if newly recorded, 0 if duplicate.
--
-- Spec: docs/03-architecture.md §15.
-- A retry from the same client (same clientActionId) is a no-op — the
-- stored timestamp stays the FIRST action's. EXPIRE is refreshed on every
-- insert; 120 s comfortably outlives the longest expected phase (~90 s).
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then return 0 end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[1], 120)
return 1
