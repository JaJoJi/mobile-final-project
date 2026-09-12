-- ws_rate_limit.lua
-- Atomic, cross-instance sliding-window rate limiter for WebSocket messages.
--
-- KEYS[1] = sorted set of hits for one user
-- KEYS[2] = per-user sequence used to make members unique
-- ARGV[1] = window size in milliseconds
--
-- Redis TIME is used instead of an application clock so every Nest replica
-- evaluates the same window even when host clocks differ.

local time = redis.call('TIME')
local now = (tonumber(time[1]) * 1000) + math.floor(tonumber(time[2]) / 1000)
local window = tonumber(ARGV[1])
local cutoff = now - window

redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', cutoff)

local sequence = redis.call('INCR', KEYS[2])
redis.call('ZADD', KEYS[1], now, tostring(now) .. ':' .. tostring(sequence))

-- Keep both keys only slightly longer than the active window. This replaces
-- process-local disconnect cleanup and bounds storage even after a hard crash.
redis.call('PEXPIRE', KEYS[1], window + 1000)
redis.call('PEXPIRE', KEYS[2], window + 1000)

return redis.call('ZCARD', KEYS[1])
