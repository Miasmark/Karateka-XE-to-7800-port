-- at frame AT: the shown buffer's first bytes of rows 0-3 and 40, and each
-- write to BACKGRND ($20) and P0C1-3/P1C1-3 in that frame, with the scanline.
-- To bkcheck.log. WITHPLAY=1: playkey drives.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local scr = M.screens[":screen"]
local AT = tonumber(os.getenv("AT") or "5000")
local f, shown, log = 0, nil, {}
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) shown = d; return d end)
W = mem:install_write_tap(0x0020, 0x0027, "col", function(a, d)
  if f == AT then log[#log + 1] = string.format("line %3d  $%02X <- %02X", scr:vpos(), a, d) end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == AT + 1 then
    local o = io.open("bkcheck.log", "w")
    local base = (shown == 0x22) and 0x5808 or 0x4010
    for _, r in ipairs({0, 1, 2, 3, 20, 40, 60}) do
      local t = {}
      for c = 0, 39 do t[#t + 1] = string.format("%02X", mem:read_u8(base + 40 * r + c)) end
      o:write(string.format("row %2d: %s\n", r, table.concat(t, " ")))
    end
    for _, l in ipairs(log) do o:write(l .. "\n") end
    o:close()
    M.video:snapshot()
  end
  if f > AT + 2 then M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
