-- the sound driver's state at frames AT (comma list): engine $7400-$7421
-- (XE $2400-$2421), the common variables $1A80-$1AA0 (XE $0AF6-$0AFF,
-- $0B26, $0C4C-$0C50, $0F09-$0F17, carved) and zero page $00/$01, $04/$05 (the
-- driver's pointers, through the ZP map); to snddump.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
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
    o:write(string.format("f%d\n  $7400-$7421: %s\n  $1A80-$1AA0: %s\n  zp $00/01 %02X%02X  $04/05 %02X%02X\n", f,
      hex(0x7400, 0x7421), hex(0x1A80, 0x1AA0), mem:read_u8(ZP[1]), mem:read_u8(ZP[0]), mem:read_u8(ZP[5]), mem:read_u8(ZP[4])))
    o:flush()
  end
  if f >= last then o:close(); M:exit() end
end)
