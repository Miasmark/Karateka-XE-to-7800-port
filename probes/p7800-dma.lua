-- MARIA's DMA in play, measured and modelled, per BLOCK frames (default 100):
--  executed: 6502 cycles actually run (base counts + taken branches + page
--            crossings), in and out of the NMI;
--  slow:     extra cycles for TIA/RIOT accesses (they run at 1.19 MHz: +0.5
--            cycle each);
--  measured DMA = 29868 (a frame, 262 lines of 114) - executed - slow;
--  model:    the display list list on screen priced with the toolkit's
--            dmabudget.py constants (per line, zone, entry, byte, DLI).
-- playkey.lua drives the input (its env applies: SCENE, INJECT, SHORT, KEYN).
-- To dma.log; stops after END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local PCs, SPs, Xs, Ys = cpu.state["PC"], cpu.state["SP"], cpu.state["X"], cpu.state["Y"]
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
local MODE = {"imp","izx","imp","izx","zp","zp","zp","zp","imp","imm","acc","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx","abs","izx","imp","izx","zp","zp","zp","zp","imp","imm","acc","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx","imp","izx","imp","izx","zp","zp","zp","zp","imp","imm","acc","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx","imp","izx","imp","izx","zp","zp","zp","zp","imp","imm","acc","imm","ind","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx","imm","izx","imm","izx","zp","zp","zp","zp","imp","imm","imp","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpy","zpy","imp","aby","imp","aby","abx","abx","aby","aby","imm","izx","imm","izx","zp","zp","zp","zp","imp","imm","imp","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpy","zpy","imp","aby","imp","aby","abx","abx","aby","aby","imm","izx","imm","izx","zp","zp","zp","zp","imp","imm","imp","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx","imm","izx","imm","izx","zp","zp","zp","zp","imp","imm","imp","imm","abs","abs","abs","abs","rel","izy","imp","izy","zpx","zpx","zpx","zpx","imp","aby","imp","aby","abx","abx","abx","abx"}
local PEN = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1,1,0,0}
local BLOCK = tonumber(os.getenv("BLOCK") or "100")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local FRAME = 29868
local PER_LINE, PER_ZONE, PER_OBJ, PER_BYTE, FIVE_XTRA, DLI_COST = 5.633, 1.678, 2.081, 0.744, 0.483, 16.6
local function r(a) return mem:read_u8(a) end
local executed, slow, model, nframes, f = 0, 0, 0, 0, 0
local lastpc, lastop = -1, 0
local lines_drawn = 0
local o = io.open("dma.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "dmac", function(a, d)
  if a ~= PCs.value then return d end
  if f < FROM then return d end
  -- the previous instruction's branch outcome
  if lastpc >= 0 and MODE[lastop + 1] == "rel" and a ~= ((lastpc + 2) & 0xFFFF) then
    executed = executed + 1
    if (a & 0xFF00) ~= ((lastpc + 2) & 0xFF00) then executed = executed + 1 end
  end
  executed = executed + CYC[d + 1]
  if PEN[d + 1] == 1 then
    local m, base, idx = MODE[d + 1], 0, 0
    if m == "abx" or m == "aby" then
      base = r(a + 1) | (r(a + 2) << 8)
      idx = (m == "abx") and Xs.value or Ys.value
    elseif m == "izy" then
      local z = r(a + 1)
      base = r(z) | (r((z + 1) & 0xFF) << 8)
      idx = Ys.value
    end
    if ((base + idx) & 0xFF00) ~= (base & 0xFF00) then executed = executed + 1 end
  end
  lastpc, lastop = a, d
  return d end)
local function slowtap(a, d) if f >= FROM then slow = slow + 0.5 end return d end
S1 = mem:install_read_tap(0x0000, 0x001F, "slow1", slowtap)
S2 = mem:install_write_tap(0x0000, 0x001F, "slow2", slowtap)
S3 = mem:install_read_tap(0x0280, 0x02FF, "slow3", slowtap)
S4 = mem:install_write_tap(0x0280, 0x02FF, "slow4", slowtap)
-- the list on screen: the DLL at the last applied DPPH/DPPL
local function price()
  local dll = (r(S.S_PDPPH) << 8) | r(S.S_PDPPL)
  local total, drawn = 0, 0
  for z = 0, 242 do
    local e = dll + 3 * z
    local fl = r(e)
    local lines = (fl & 0x0F) + 1
    local dl = (r(e + 1) << 8) | r(e + 2)
    local objs, bytes, five = 0, 0, 0
    for k = 1, 16 do
      local b1 = r(dl + 1)
      if b1 == 0 then break end
      if (b1 & 0x1F) == 0 then       -- 5-byte header: width in byte 4
        local w = 32 - (r(dl + 3) & 0x1F)
        objs, bytes, five = objs + 1, bytes + w, five + 1
        dl = dl + 5
      else
        local w = 32 - (b1 & 0x1F)
        objs, bytes = objs + 1, bytes + w
        dl = dl + 4
      end
    end
    if objs > 0 then drawn = drawn + lines end
    total = total + lines * (PER_LINE + objs * PER_OBJ + bytes * PER_BYTE + five * FIVE_XTRA) + PER_ZONE
      + ((fl & 0x80) ~= 0 and DLI_COST or 0)
  end
  return total, drawn
end
emu.register_frame_done(function()
  f = f + 1
  if f <= FROM then executed, slow = 0, 0; return end
  local m, d = price()
  model, nframes, lines_drawn = model + m, nframes + 1, d
  if nframes == BLOCK then
    local ex, sl = executed / BLOCK, slow / BLOCK
    o:write(string.format("f%d flip %d scene %d: executed %.0f slow %.0f measured DMA %.0f model %.0f (%d lines drawn)\n",
      f, PLAYKEY_N or 0, r(0xD0), ex, sl, FRAME - ex - sl, model / BLOCK, lines_drawn))
    o:flush()
    executed, slow, model, nframes = 0, 0, 0, 0
  end
  if f >= END then o:close(); M:exit() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
