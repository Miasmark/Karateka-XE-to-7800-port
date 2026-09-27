-- screenshots of the original at chosen frames (FRAMES, comma list) while a
-- recording plays; CHEAT: the script it was recorded with; stops after the
-- last. Snapshots in MAME's snapshot directory (xegs/NNNN.png).
local M = manager.machine
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local want, last = {}, 0
for t in (os.getenv("FRAMES") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if want[f] then M.video:snapshot() end
  if f >= last then M:exit() end
end)
