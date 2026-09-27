-- xe-invincible.lua -- Karateka XEGS (MAME `xegs`): version 1 of the playthrough
-- cheat, SUPERSEDED by xe-easy.lua and kept only because xe-01-inv.inp was
-- recorded with it and replays only with it.
--
-- Its flaw: blocking every lowering of $B6 also blocks the game setting a
-- lower health for each new opponent ($7BB8 & co.), so the refill at $0C28,
-- which counts up until $B6 equals the maximum in $B0, never stops: health
-- runs to 255 and sticks there. It also does not stop the instant deaths
-- (they are decided before $B6 is written), and the gate in scene 2 then
-- leaves the player lying under it indefinitely.
--
--
-- $00B6 is the player's health: 14 at the start of a life, one less per hit,
-- 0 is dead (found 2026-09-24 by matching RAM against the status-bar arrows;
-- see FINDINGS.md). This refuses every write that would lower it, so hits
-- land but cost nothing. Writes that raise it (a new life, a refill) go
-- through, so the game's own resets are untouched. Inactive in scene 0
-- (title and story).
--
-- A recording made with this running only replays with it running too:
-- the game's state differs from the first hit on. The batch files name such
-- recordings *-inv.inp and load this script again for playback.
--
-- Other scripts can pull it in with dofile() before their own taps.

local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = M.devices[":maincpu"].spaces["program"]

-- a global: a tap held only in a local is garbage-collected
XE_INVINCIBLE = mem:install_write_tap(0x00B6, 0x00B6, "xe-invincible", function(a, d)
  local cur = mem:read_u8(0x00B6)
  if d < cur and mem:read_u8(0x00D0) ~= 0 then return cur end
  return d
end)
