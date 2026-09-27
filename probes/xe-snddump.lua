-- the original's sound driver state at frames AT (comma list): $2400-$2421,
-- $0AF6-$0AFF, $0F09-$0F17 and $00-$05; CHEAT first; to snddump.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local want, last = {}, 0
for t in (os.getenv("AT") or ""):gmatch("%d+") do local n = tonumber(t); want[n] = true; if n > last then last = n end end
local f = 0
local o = io.open("snddump.log", "w")
local function hex(lo, hi)
  local t = {}
  for a = lo, hi do t[#t + 1] = string.format("%02X", mem:read_u8(a)) end
  return table.concat(t, " ")
end
emu.register_frame_done(function()
  f = f + 1
  if want[f] then
    o:write(string.format("f%d D0=%02X hp %02X/%02X\n  $2400-$2421: %s\n  $0AF6-$0AFF: %s  $0F09-$0F17: %s\n  $00-$05: %s\n", f,
      mem:read_u8(0xD0), mem:read_u8(0xB6), mem:read_u8(0xB7), hex(0x2400, 0x2421), hex(0x0AF6, 0x0AFF), hex(0x0F09, 0x0F17), hex(0, 5)))
    o:flush()
  end
  if f >= last then o:close(); M:exit() end
end)
