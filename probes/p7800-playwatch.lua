-- the scripted player (as p7800-play.lua) with p7800-watch.lua's write log
-- (WATCH range) from frame FROM on
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local START = tonumber(os.getenv("START") or "1800")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "3000")
local lo, hi = (os.getenv("WATCH") or "1E0A-1E0A"):match("(%x+)-(%x+)")
lo, hi = tonumber(lo, 16), tonumber(hi, 16)
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local f = 0
local o = io.open("watch.log", "w")
W = mem:install_write_tap(lo, hi, "pw", function(a, d)
  if f >= FROM then
    local pc = cpu.state["PC"].value
    o:write(string.format("f%d PC=%04X %04X<-%02X b%d %s\n", f, pc, a, d, mem:read_u8(SYM_ADDR.S_BANK), SYM_NAME[pc] or ""))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f >= END then o:close(); M:exit() end
end)
