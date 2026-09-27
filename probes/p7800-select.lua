-- press the console's Select (SWCHB bit 1, active low) for HOLD frames
-- (default 10) at frame AT (default 400) by answering the game's SWCHB reads,
-- then p7800-run.lua's log and snapshots (its END), plus p7800-firstover.lua's
-- stray-write watch (its WLO/WHI/BLITONLY)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AT") or "400")
local HOLD = tonumber(os.getenv("HOLD") or "10")
local fsel = 0
SEL = mem:install_read_tap(0x0282, 0x0282, "select", function(a, d)
  if fsel >= AT and fsel < AT + HOLD then return d & 0xFD end
  return d end)
emu.register_frame_done(function() fsel = fsel + 1 end)
dofile(os.getenv("PROBES") .. "/p7800-firstover.lua")
dofile(os.getenv("PROBES") .. "/p7800-run.lua")
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
