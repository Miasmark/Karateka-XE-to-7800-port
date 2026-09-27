-- the last N instruction fetches before the 7800 build goes wrong: stops at
-- the first fetch from console RAM/TIA/MARIA space ($0000-$3FFF; no code runs
-- there), of a BRK or JAM opcode, or with the stack below SPMIN (default
-- 128); each line PC:opcode, SP, bank, and the system label if any
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local N = tonumber(os.getenv("N") or "3000")
local SPMIN = tonumber(os.getenv("SPMIN") or "128")
-- BADLO/BADHI (hex): also stop at a fetch in this range (e.g. sprite data)
local NOLOW = os.getenv("NOLOW") ~= nil   -- only the BADLO-BADHI and stack checks
local BADLO = tonumber(os.getenv("BADLO") or "10000", 16)
local BADHI = tonumber(os.getenv("BADHI") or "10000", 16)
local END = tonumber(os.getenv("END") or "600")
local ring, n, f, done, armed = {}, 0, 0, false, false
local o = io.open("crash.log", "w")
TC = mem:install_read_tap(0x0000, 0xFFFF, "ring", function(a, d)
  if done or a ~= PCs.value then return d end
  if a == S.Reset then armed = true end
  if not armed then return d end
  n = n + 1
  local sp = SPs.value & 0xFF
  ring[(n - 1) % N + 1] = string.format("f%d %04X:%02X S%02X b%d %s", f, a, d, sp, mem:read_u8(S.S_BANK), SYM_NAME[a] or "")
  local jam = d == 0x00 or (d & 0x0F) == 0x02 and d ~= 0xA2 and d ~= 0x82 and d ~= 0xC2 and d ~= 0xE2
  if (a < 0x4000 and not NOLOW) or (jam and not NOLOW) or (sp < SPMIN and n > 20) or (a >= BADLO and a < BADHI) then
    done = true
    o:write(string.format("stop at frame %d, PC=%04X SP=%02X\n", f, a, sp))
    for i = math.max(1, n - N + 1), n do o:write(ring[(i - 1) % N + 1] .. "\n") end
    o:close()
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then if not done then o:write("no stop\n"); o:close() end; M:exit() end
end)
-- WITHPLAY=1: drive the input with playkey.lua (its env applies)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
