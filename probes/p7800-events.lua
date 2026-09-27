-- entries to the port's system routines (a label reached by JSR, JMP or a far
-- transfer such as an interrupt), with stack depth, NMI count, frame guard
-- state and the game's display list; snapshots every 100 frames; stops after
-- END frames
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local END = tonumber(os.getenv("END") or "300")
local LIMIT = tonumber(os.getenv("LIMIT") or "6000")
local S = SYM_ADDR
local function r(x) return mem:read_u8(x) end
local f, n, prev = 0, 0, 0
local o = io.open("events.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "ev", function(a, d)
  if a ~= PCs.value then return d end
  local op, far = r(prev), math.abs(a - prev) > 130
  local from = prev; prev = a
  if SYM_NAME[a] and (far or op == 0x20 or ((op == 0x4C or op == 0x6C) and a > from)) and n < LIMIT then
    n = n + 1
    o:write(string.format("f%d %s from %04X S%02X nmic=%d busy=%d pend=%d frames=%d dl=%02X%02X\n", f, SYM_NAME[a], from,
      SPs.value & 0xFF, r(S.S_NMICOUNT), r(S.S_BUSY), r(S.S_PEND), r(S.S_FRAMES), r(S.S_DLIST + 1), r(S.S_DLIST)))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f % 100 == 0 then M.video:snapshot() end
  if f >= END then o:close(); M:exit() end
end)
