-- CPU cycles executed per frame (base 6502 counts, +1 for a taken branch;
-- index page crossings not counted, so slightly low), split main / NMI; the
-- rest of the frame's cycles went to display DMA or were stolen otherwise.
-- Either machine. Per EVERY frames (default 50) to cycles.log.
-- (Generated opcode table: tools/m6502.py CYCLES.)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local EVERY = tonumber(os.getenv("EVERY") or "50")
local END = tonumber(os.getenv("END") or "600")
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
local BR = {}
for _, op in ipairs({16,48,80,112,144,176,208,240}) do BR[op] = true end
local f, nmi, irq_sp = 0, -1, nil
local START = tonumber(os.getenv("START") or "-1")   -- the census's scripted player from this frame
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local main, inn, lastpc, lastop, lastnmi = 0, 0, -1, 0, false
local o = io.open("cycles.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "cyc", function(a, d)
  if a ~= PCs.value then return d end
  -- the previous instruction: a taken branch lands away from pc+2
  if lastpc >= 0 and BR[lastop] and a ~= ((lastpc + 2) & 0xFFFF) then
    if lastnmi then inn = inn + 1 else main = main + 1 end
  end
  local sp = SPs.value & 0xFF
  if irq_sp and sp >= irq_sp then irq_sp = nil end
  if a == nmi and not irq_sp then irq_sp = sp + 3 end
  local c = CYC[d + 1]
  if irq_sp then inn = inn + c else main = main + c end
  lastpc, lastop, lastnmi = a, d, irq_sp ~= nil
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if START >= 0 and f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  nmi = mem:read_u8(0xFFFA) | (mem:read_u8(0xFFFB) << 8)
  if f % EVERY == 0 then
    o:write(string.format("f%d per frame: main %d nmi %d total %d\n", f, main // EVERY, inn // EVERY, (main + inn) // EVERY))
    main, inn = 0, 0
    o:flush()
  end
  if f >= END then o:close(); M:exit() end
end)
