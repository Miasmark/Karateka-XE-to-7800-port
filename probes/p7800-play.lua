-- the census's scripted player on the 7800 build: from frame START (default
-- 1800) hold right 40 of every 90 frames and press fire at 60-63; snapshots
-- every SNAP frames (default 100); a state line every 50 frames (loaded
-- scene bank, $D0, frames, PC) to play.log; stops after END frames.
-- LIST=1 lists the machine's input names instead.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local START = tonumber(os.getenv("START") or "1800")
local SNAP = tonumber(os.getenv("SNAP") or "100")
local END = tonumber(os.getenv("END") or "4000")
local ZD0 = tonumber(os.getenv("ZD0") or "D0", 16)
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local o = io.open("play.log", "w")
if os.getenv("LIST") then
  for name, _ in pairs(fields) do o:write(name .. "\n") end
  o:close(); M:exit()
end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f > START then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f % 50 == 0 then
    o:write(string.format("f%d scenebank=%d D0=%02X frames=%d PC=%04X SP=%02X\n", f, mem:read_u8(S.S_SCENEBANK),
      mem:read_u8(ZD0), mem:read_u8(S.S_FRAMES), cpu.state["PC"].value, cpu.state["SP"].value & 0xFF))
    o:flush()
  end
  if f % SNAP == 0 then M.video:snapshot() end
  if f >= END then o:close(); M:exit() end
end)
