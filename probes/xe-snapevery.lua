-- a snapshot every EVERY frames from FROM to END (no input), for the
-- original (port/runxe.sh); numbered from 0
local M = manager.machine
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local EVERY = tonumber(os.getenv("EVERY") or "1")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f <= END and (f - FROM) % EVERY == 0 then M.video:snapshot() end
  if f >= END then M:exit() end
end)
