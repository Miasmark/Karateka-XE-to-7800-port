-- the 7800 build's state every 20 frames (PC, SP, banks, frame counters, the
-- game's display list and vectors, a histogram of PC pages over the last 20
-- frames), snapshots every 100 frames, and any write into the ROM window by
-- non-system code (a bank switch the game did not mean); stops after END frames
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "300")
local function r(x) return mem:read_u8(x) end
local function w16(x) return r(x) | (r(x + 1) << 8) end
local f = 0
local o = io.open("run.log", "w")
local wrom, pages = {}, {}
W = mem:install_write_tap(0x8000, 0xBFFF, "wrom", function(a, d)
  local pc = PCs.value
  if pc < S.SysZpSwap or pc > S.DLA_BASE then
    local k = string.format("%04X->%04X", pc, a)
    wrom[k] = (wrom[k] or 0) + 1
  end
  return d end)
T = mem:install_read_tap(0x0000, 0xFFFF, "pc", function(a, d)
  if a == PCs.value then local p = a >> 8; pages[p] = (pages[p] or 0) + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f % 20 == 0 then
    local h = {}
    for p, c in pairs(pages) do h[#h + 1] = {p, c} end
    table.sort(h, function(x, y) return x[2] > y[2] end)
    local hs = ""
    for i = 1, math.min(5, #h) do hs = hs .. string.format(" %02X:%d", h[i][1], h[i][2]) end
    pages = {}
    o:write(string.format("f%d PC=%04X SP=%02X bank=%d scene=%d frames=%d busy=%d pend=%d dl=%04X nmien=%02X vbi=%04X dli=%04X |%s\n",
      f, PCs.value, cpu.state["SP"].value & 0xFF, r(S.S_BANK), r(S.S_SCENEBANK), r(S.S_FRAMES), r(S.S_BUSY),
      r(S.S_PEND), w16(S.S_DLIST), r(S.S_NMIEN), w16(S.S_VVBLKI), w16(S.S_VDSLST), hs))
    o:flush()
  end
  if f % 100 == 0 then M.video:snapshot() end
  if f >= END then
    for k, v in pairs(wrom) do o:write("ROM-window write " .. k .. " x" .. v .. "\n") end
    o:close(); M:exit()
  end
end)
