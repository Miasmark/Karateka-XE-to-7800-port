-- memory at frame AT (default 176): PEEK is a list of hex ranges "7000-701F,4010-401F"
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AT") or "176")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local o = io.open("peek.log", "w")
    for lo, hi in (os.getenv("PEEK") or "7000-701F"):gmatch("(%x+)-(%x+)") do
      lo, hi = tonumber(lo, 16), tonumber(hi, 16)
      for a = lo, hi, 16 do
        local s = string.format("%04X:", a)
        for i = 0, 15 do if a + i <= hi then s = s .. string.format(" %02X", mem:read_u8(a + i)) end end
        o:write(s .. "\n")
      end
    end
    o:close(); M:exit()
  end
end)
