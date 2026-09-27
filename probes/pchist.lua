-- instruction fetches by PC outside the NMI (INNMI=1: inside it) between
-- frames FROM and TO, top 40 to pchist.log; either machine. START (frame)
-- turns on the census's scripted player.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local FROM, TO = tonumber(os.getenv("FROM") or "300"), tonumber(os.getenv("TO") or "400")
local f, nmi, irq_sp, h = 0, -1, nil, {}
local INNMI = os.getenv("INNMI") ~= nil
local START = tonumber(os.getenv("START") or "-1")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
T = mem:install_read_tap(0x0000, 0xFFFF, "pch", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  local sp = SPs.value & 0xFF
  if irq_sp and sp >= irq_sp then irq_sp = nil end
  if a == nmi and not irq_sp then irq_sp = sp + 3 end
  if (irq_sp ~= nil) == INNMI then h[a] = (h[a] or 0) + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if START >= 0 and f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  nmi = mem:read_u8(0xFFFA) | (mem:read_u8(0xFFFB) << 8)
  if f >= TO then
    local t = {}
    for a, c in pairs(h) do t[#t + 1] = {a, c} end
    table.sort(t, function(x, y) return x[2] > y[2] end)
    local o = io.open("pchist.log", "w")
    for i = 1, math.min(40, #t) do o:write(string.format("%04X %d\n", t[i][1], t[i][2])) end
    o:close(); M:exit()
  end
end)
