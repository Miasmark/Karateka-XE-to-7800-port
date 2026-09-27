-- every write into the two framebuffers by game code, in order, as
-- "PC buffer offset value blit" (blit: how many blits have started, counted
-- at $29E0 as in blitlog.lua) with PC in XEGS terms (the 7800 engine at
-- $7000-$7FFF shown at its XEGS address; other PCs raw) and the offset from
-- the buffer's base; to fbwrites.log; stops after END frames or LIMIT writes
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local A, B = xe and 0x4808 or 0x5808, xe and 0x3010 or 0x4010
local SIZE = 0x17E8
local END = tonumber(os.getenv("END") or "600")
local LIMIT = tonumber(os.getenv("LIMIT") or "200000")
local f, n, blits = 0, 0, 0
local START = xe and 0x29E0 or 0x79E0
BT = mem:install_read_tap(START, START, "fbblit", function(a, d)
  if a == PCs.value then blits = blits + 1 end
  return d end)
local o = io.open("fbwrites.log", "w")
local function pcx(a)
  if xe then return a end
  if a >= 0x7000 and a < 0x7203 then return a - 0x6000 end
  if a >= 0x7300 and a < 0x8000 then return a - 0x5000 end
  return a
end
local function tap(base, name)
  return mem:install_write_tap(base, base + SIZE - 1, "fb" .. name, function(a, d)
    if n < LIMIT then
      n = n + 1
      o:write(string.format("%04X %s %04X %02X %d\n", pcx(PCs.value), name, a - base, d, blits))
    end
    return d end)
end
TA = tap(A, "A")
TB = tap(B, "B")
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
