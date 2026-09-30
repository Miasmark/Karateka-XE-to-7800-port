-- a snapshot at the end of every EVERY-th frame (default 1) from FROM to END (no input; the
-- snapshots are numbered from 0, so frame = FROM + number). WITHPLAY=1
-- drives input with playkey.lua (its env applies).
local M = manager.machine
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local EVERY = tonumber(os.getenv("EVERY") or "1")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f <= END and (f - FROM) % EVERY == 0 then M.video:snapshot() end
  if f >= END then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
