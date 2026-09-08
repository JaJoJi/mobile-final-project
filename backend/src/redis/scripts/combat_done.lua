-- combat_done.lua
-- Idempotent per-player combat-done ack + total count.
-- KEYS[1] = match:<id>:combat-done
-- ARGV[1] = playerId
-- ARGV[2] = epoch ms
-- Returns count of distinct acks after this insert (1 or 2).
--
-- Spec: docs/03-architecture.md §13.2, race R12.
-- A second insert for the same player is a no-op — HEXISTS short-circuits
-- before HSET, so the stored epoch stays the FIRST ack's timestamp.
-- EXPIRE is refreshed on every insert so an abandoned match cleans itself up.
if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then
  return tonumber(redis.call('HLEN', KEYS[1]))
end
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
redis.call('EXPIRE', KEYS[1], 90)
return tonumber(redis.call('HLEN', KEYS[1]))
