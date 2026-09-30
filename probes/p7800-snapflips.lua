-- a snapshot at the end of the frame after every EVERY-th buffer flip (a
-- DPPH change), so two builds that run at different speeds can be compared
-- picture by picture; no input. Snapshots are named by the flip count in
-- snapflips.log. END frames.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "9000")
local EVERY = tonumber(os.getenv("EVERY") or "10")
local f, flips, last, pend = 0, 0, nil, false
local log = io.open("snapflips.log", "w")
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if last and d ~= last then
    flips = flips + 1
    if flips % EVERY == 0 then pend = true end
  end
  last = d
  return d end)
local n = 0
emu.register_frame_done(function()
  f = f + 1
  if pend then
    pend = false
    M.video:snapshot()
    log:write(string.format("%04d flip %d frame %d\n", n, flips, f)); log:flush()
    n = n + 1
  end
  if f >= END then log:close(); M:exit() end
end)
