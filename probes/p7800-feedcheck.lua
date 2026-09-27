-- p7800-inputlog.lua MODE=feed together with p7800-firstover.lua (stray
-- writes; its WLO/WHI/BLITONLY env) and a screenshot every SNAPEVERY frames
dofile(os.getenv("PROBES") .. "/p7800-inputlog.lua")
dofile(os.getenv("PROBES") .. "/p7800-firstover.lua")
local M = manager.machine
local EVERY = tonumber(os.getenv("SNAPEVERY") or "50")
local fs = 0
emu.register_frame_done(function()
  fs = fs + 1
  if fs % EVERY == 0 then M.video:snapshot() end
end)
