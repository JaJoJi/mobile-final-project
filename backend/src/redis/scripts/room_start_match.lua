-- room_start_match.lua
-- Atomic Room -> Match handoff claim (#259).
-- KEYS[1] = room:<roomId>
-- KEYS[2] = room:<roomId>:handoff (claim key)
-- ARGV[1] = claim token (random per attempt)
-- ARGV[2] = claim TTL seconds
-- Returns {ownerId, guestId} to the single claim winner; 0 if the room is
-- gone; -1 if not full; -2 if players are missing; -3 if already claimed.
--
-- The claim is a short-lived key (auto-expiry bounds a crashed worker), NOT
-- a room state — the room stays `full` so a failed handoff remains
-- retryable. Match creation itself (PostgreSQL + runtime) happens outside
-- Lua; exactly-once comes from exactly-one-claim plus the idempotent
-- room_match_done.lua record step.
if redis.call('HEXISTS', KEYS[1], 'roomId') == 0 then return 0 end
if redis.call('HGET', KEYS[1], 'status') ~= 'full' then return -1 end
local owner = redis.call('HGET', KEYS[1], 'ownerId')
local guest = redis.call('HGET', KEYS[1], 'guestId')
if owner == false or owner == '' or guest == false or guest == '' then return -2 end
if redis.call('SET', KEYS[2], ARGV[1], 'NX', 'EX', ARGV[2]) == false then return -3 end
return {owner, guest}
