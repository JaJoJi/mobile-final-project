-- room_match_abort.lua
-- Release a handoff claim owned by this attempt (#259 compensation).
-- KEYS[1] = room:<roomId>:handoff (claim key)
-- ARGV[1] = claim token
-- Deletes only our own claim (token-checked); returns 1 if released.
-- The room itself is untouched and stays retryable.
if redis.call('GET', KEYS[1]) == ARGV[1] then
  return redis.call('DEL', KEYS[1])
end
return 0
