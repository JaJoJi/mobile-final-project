-- match_pair.lua
-- Atomic matchmaking pop — takes the two longest-waiting entries.
-- KEYS[1] = matchmaking:queue (ZSET, score = join timestamp)
-- Returns array of [userId1, userId2], or [] if fewer than 2 members.
--
-- Spec: docs/03-architecture.md §13.3, race R4 + R5.
-- ZRANGE 0 1 + ZREM is two ops, but inside Lua the script is atomic —
-- no other client can interleave a ZRANGE / ZADD / ZREM between them.
-- Pure FIFO (current implementation); ELO is tracked on `users.rating`
-- but not used for matchmaking (display-only, updated on match end).
local members = redis.call('ZRANGE', KEYS[1], 0, 1)
if #members < 2 then return {} end
redis.call('ZREM', KEYS[1], members[1], members[2])
return members
