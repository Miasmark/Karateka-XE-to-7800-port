-- the original: a snapshot every EVERY frames (default 100) until END
local M = manager.machine
local EVERY = tonumber(os.getenv("EVERY") or "100")
local END = tonumber(os.getenv("END") or "900")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f % EVERY == 0 then M.video:snapshot() end
  if f >= END then M:exit() end
end)
