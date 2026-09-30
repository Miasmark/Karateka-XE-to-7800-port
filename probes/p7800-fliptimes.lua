-- the frame of every buffer flip (a DPPH change), to fliptimes.log as
-- "flip frame" lines, until END frames or flip LASTFLIP. WITHPLAY=1 drives
-- input with playkey.lua (its env applies; KEYN beyond LASTFLIP keeps it from
-- stopping first).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "20000")
local LAST = tonumber(os.getenv("LASTFLIP") or "100000")
local f, flips, last = 0, 0, nil
local o = io.open("fliptimes.log", "w")
D = mem:install_write_tap(0x002C, 0x002C, "ft", function(a, d)
  if last and d ~= last then
    flips = flips + 1
    o:write(string.format("%d %d\n", flips, f)); o:flush()
  end
  last = d
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END or flips >= LAST then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
