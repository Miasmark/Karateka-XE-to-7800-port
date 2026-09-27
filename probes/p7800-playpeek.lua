-- the scripted player (p7800-play.lua's input) with a memory peek at frame AT
-- (PEEK ranges as in p7800-peek.lua), to peek.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local START = tonumber(os.getenv("START") or "1800")
local AT = tonumber(os.getenv("AT") or "3000")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f == AT then
    local o = io.open("peek.log", "w")
    for lo, hi in (os.getenv("PEEK") or "1E00-1E4F"):gmatch("(%x+)-(%x+)") do
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
