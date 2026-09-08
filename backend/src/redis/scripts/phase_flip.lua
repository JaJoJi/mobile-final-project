-- phase_flip.lua
-- Atomic CAS phase transition for the match runtime hash.
-- KEYS[1] = match:<id>:runtime
-- ARGV[1] = expectedPhase   ('shop_place' / 'battle' / 'resolved' / 'finished')
-- ARGV[2] = newPhase
-- ARGV[3] = instanceId (for combatLockInstance tag when entering battle)
-- Returns 1 if flipped, 0 if phase didn't match (lost CAS).
--
-- Spec: docs/03-architecture.md §13.1, race R6 + R10.
local cur = redis.call('HGET', KEYS[1], 'phase')
if cur ~= ARGV[1] then return 0 end
redis.call('HSET', KEYS[1], 'phase', ARGV[2])
if ARGV[2] == 'battle' then
  redis.call('HSET', KEYS[1], 'combatLockInstance', ARGV[3])
  -- combat-lock key is acquired via SET NX EX OUTSIDE this script (§11.3)
end
return 1
