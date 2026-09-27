-- per EVERY frames (default 50): fetches of each PC in PCS (hex, comma list),
-- all instruction fetches, and those inside the NMI (from the NMI vector until
-- the stack is back); either machine; to pccount.log. START (frame) turns on
-- the census's scripted player (hold right 40 of 90 frames, fire at 60-63).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local EVERY = tonumber(os.getenv("EVERY") or "50")
local END = tonumber(os.getenv("END") or "1500")
local watch, cnt = {}, {}
for h in (os.getenv("PCS") or ""):gmatch("%x+") do watch[tonumber(h, 16)] = true end
local f, all, innmi, nmi, irq_sp = 0, 0, 0, -1, nil
local START = tonumber(os.getenv("START") or "-1")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local o = io.open("pccount.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "pcc", function(a, d)
  if a ~= PCs.value then return d end
  all = all + 1
  local sp = SPs.value & 0xFF
  if irq_sp and sp >= irq_sp then irq_sp = nil end
  if a == nmi and not irq_sp then irq_sp = sp + 3 end
  if irq_sp then innmi = innmi + 1 end
  if watch[a] then cnt[a] = (cnt[a] or 0) + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if START >= 0 and f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  nmi = mem:read_u8(0xFFFA) | (mem:read_u8(0xFFFB) << 8)   -- the cartridge's, once it is in
  if f % EVERY == 0 then
    local s = ""
    for a, _ in pairs(watch) do s = s .. string.format(" %04X:%d", a, cnt[a] or 0) end
    o:write(string.format("f%d insns %d in-nmi %d%s\n", f, all, innmi, s))
    all, innmi, cnt = 0, 0, {}
    o:flush()
  end
  if f >= END then o:close(); M:exit() end
end)
