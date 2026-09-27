-- per 50 frames: how many times the game's vertical-blank handler ($0F18,
-- at $9F18) and DLI handler ($1026, at $7026) ran, and how many vertical
-- blanks the system dropped (the last still running) or deferred; to rate.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "1200")
local f, vbi, dli, nmi, busy = 0, 0, 0, 0, 0
local o = io.open("rate.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "rate", function(a, d)
  if a ~= PCs.value then return d end
  if a == 0x9F18 then vbi = vbi + 1
  elseif a == 0x7026 then dli = dli + 1
  elseif a == S.NmiVbi then nmi = nmi + 1
  elseif a == S.BuildDll then busy = busy + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f % 50 == 0 then
    o:write(string.format("f%d vbi-nmi %d game-vbi %d game-dli %d builds %d\n", f, nmi, vbi, dli, busy))
    vbi, dli, nmi, busy = 0, 0, 0, 0
  end
  if f >= END then o:close(); M:exit() end
end)
