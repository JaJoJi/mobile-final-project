-- room_join.lua
-- Atomic final-slot claim for a private room (#258).
-- KEYS[1] = room:<roomId>
-- KEYS[2] = user:room:<guestId>
-- ARGV[1] = guestId
-- ARGV[2] = roomId
-- ARGV[3] = user-mapping TTL seconds
-- Returns 1 if joined, 0 if the room is gone, -1 if full,
--          -2 if the user already has a room, -3 if not waiting,
--          -4 if the caller owns the room.
--
-- Everything the replicas could race on (slot state + membership + both
-- writes) happens inside this single script. Checks that cannot change
-- under the caller (code format, active match, queue) stay in the service.
if redis.call('HEXISTS', KEYS[1], 'roomId') == 0 then return 0 end
if redis.call('HGET', KEYS[1], 'ownerId') == ARGV[1] then return -4 end
if redis.call('EXISTS', KEYS[2]) == 1 then return -2 end
-- Occupied guest slot reports full before the status check: a full room
-- always carries its guest, so -1 is the precise answer there and -3 is
-- reserved for corrupt states (non-waiting status with an empty slot).
local guest = redis.call('HGET', KEYS[1], 'guestId')
if guest ~= false and guest ~= '' then return -1 end
if redis.call('HGET', KEYS[1], 'status') ~= 'waiting' then return -3 end
redis.call('HSET', KEYS[1], 'guestId', ARGV[1])
redis.call('HSET', KEYS[1], 'status', 'full')
redis.call('SET', KEYS[2], ARGV[2], 'EX', ARGV[3])
return 1
