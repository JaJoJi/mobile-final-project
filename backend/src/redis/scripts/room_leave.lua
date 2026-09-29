-- room_leave.lua
-- Atomic room leave for a private room (#258).
-- KEYS[1] = room:<roomId> (resolved from the caller's own user mapping)
-- KEYS[2] = user:room:<userId>
-- ARGV[1] = userId
-- Returns 1 if the guest left (room back to waiting),
--          2 if the owner destroyed the room,
--          0 if the room is gone or the caller is not a member.
--
-- Owner destroy removes every related key consistently. Key names rebuilt
-- here mirror room.types.ts (`room:code:<CODE>`, `user:room:<userId>`);
-- single-Redis deployment, no cluster hash tags involved.
if redis.call('HEXISTS', KEYS[1], 'roomId') == 0 then return 0 end
if redis.call('HGET', KEYS[1], 'ownerId') == ARGV[1] then
  local guest = redis.call('HGET', KEYS[1], 'guestId')
  local code = redis.call('HGET', KEYS[1], 'code')
  redis.call('DEL', KEYS[1])
  if code ~= false and code ~= '' then
    redis.call('DEL', 'room:code:' .. code)
  end
  redis.call('DEL', KEYS[2])
  if guest ~= false and guest ~= '' then
    redis.call('DEL', 'user:room:' .. guest)
  end
  return 2
end
if redis.call('HGET', KEYS[1], 'guestId') == ARGV[1] then
  redis.call('HSET', KEYS[1], 'guestId', '')
  redis.call('HSET', KEYS[1], 'status', 'waiting')
  redis.call('DEL', KEYS[2])
  return 1
end
return 0
