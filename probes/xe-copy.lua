-- the original: each entry to the bank-15 copy $ADCA with its source ($03/$04),
-- destination ($14/$15), end ($12/$13), the caller, and $D0; to copy.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local END = tonumber(os.getenv("END") or "6000")
local f = 0
local o = io.open("copy.log", "w")
local function r(a) return mem:read_u8(a) end
T = mem:install_read_tap(0xADCA, 0xADCA, "cp", function(a, d)
  if a ~= PCs.value then return d end
  local sp = SPs.value & 0xFF
  local ret = r(0x100 + sp + 1) | (r(0x100 + sp + 2) << 8)
  o:write(string.format("f%d copy %02X%02X -> %02X%02X end %02X%02X, called from %04X, D0=%02X\n", f, r(4), r(3),
    r(0x15), r(0x14), r(0x13), r(0x12), ret - 2, r(0xD0)))
  o:flush()
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
