-- per BLOCK frames: how many times the game's DLI handler ($1026) and
-- vertical-blank handler ($0F18) run (on the 7800 at $7026 and $9F18), plus
-- on the 7800 the NMIs and the DLIs the system dropped; playkey.lua drives
-- the input. To nmi.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local DLI, VBI = xe and 0x1026 or 0x7026, xe and 0x0F18 or 0x9F18
local BLOCK = tonumber(os.getenv("BLOCK") or "100")
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3600")
local NMI = -1
if not xe then dofile(os.getenv("PROBES") .. "/p7800-sym.lua"); NMI = SYM_ADDR.Nmi end
local f, dli, vbi, nmi = 0, 0, 0, 0
local o = io.open("nmi.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "nmic", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  if a == DLI then dli = dli + 1 elseif a == VBI then vbi = vbi + 1 elseif a == NMI then nmi = nmi + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > FROM and (f - FROM) % BLOCK == 0 then
    o:write(string.format("f%d per frame: game DLI %.2f, game VBI %.2f, NMIs %.2f\n", f, dli / BLOCK, vbi / BLOCK, nmi / BLOCK))
    o:flush(); dli, vbi, nmi = 0, 0, 0
  end
  if f >= END then o:close(); M:exit() end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- NOPLAY=1: no input (the attract sequence)
