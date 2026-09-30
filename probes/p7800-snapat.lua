-- snapshots at the ends of the frames in FRAMES (comma list); stops after
-- the last. WITHPLAY=1 drives input with playkey.lua (its env applies).
local M = manager.machine
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
