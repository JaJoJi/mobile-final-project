-- room_match_done.lua
-- Idempotent Room -> Match record + cleanup (#259).
-- KEYS[1] = room:<roomId>
-- KEYS[2] = room:code:<CODE>
-- KEYS[3] = user:room:<ownerId>
-- KEYS[4] = user:room:<guestId>
-- KEYS[5] = room:<roomId>:handoff (claim key)
-- ARGV[1] = roomId
-- ARGV[2] = matchId
-- ARGV[3] = ownerId
-- ARGV[4] = guestId
-- ARGV[5] = tombstone TTL seconds
-- Returns the recorded matchId. Running twice (retry after a crash between
-- record and cleanup, or a duplicate trigger) returns the SAME matchId
-- without touching anything twice: the room hash survives briefly as a
-- tombstone ({status = matched, matchId}) so late retries converge instead
-- of reporting not_found. The tombstone expires on its own — no permanent
-- room keys remain.
--
-- User mappings are deleted only when they still point at this room, so a
-- mapping that already moved on to a newer room is never harmed.
local recorded = redis.call('HGET', KEYS[1], 'matchId')
if recorded ~= false and recorded ~= '' then return recorded end
redis.call('HSET', KEYS[1], 'matchId', ARGV[2])
redis.call('HSET', KEYS[1], 'status', 'matched')
redis.call('DEL', KEYS[2])
redis.call('DEL', KEYS[5])
if redis.call('GET', KEYS[3]) == ARGV[1] then redis.call('DEL', KEYS[3]) end
if redis.call('GET', KEYS[4]) == ARGV[1] then redis.call('DEL', KEYS[4]) end
redis.call('EXPIRE', KEYS[1], ARGV[5])
return ARGV[2]
