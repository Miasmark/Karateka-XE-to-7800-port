-- pressat.lua, plus a memory peek at frame PEEKAT (PEEK ranges) to peek.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local PEEKAT = tonumber(os.getenv("PEEKAT") or "450")
local fr = 0
emu.register_frame_done(function()
  fr = fr + 1
  if fr == PEEKAT then
    local o = io.open("peek.log", "w")
    for lo, hi in (os.getenv("PEEK") or "1E00-1E5F"):gmatch("(%x+)-(%x+)") do
      lo, hi = tonumber(lo, 16), tonumber(hi, 16)
      for a = lo, hi, 16 do
        local s = string.format("%04X:", a)
        for i = 0, 15 do if a + i <= hi then s = s .. string.format(" %02X", mem:read_u8(a + i)) end end
        o:write(s .. "\n")
      end
    end
    o:close()
  end
end)
dofile(os.getenv("PROBES") .. "/pressat.lua")
