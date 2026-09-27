-- the original: every JSR at $28F9/$291C whose target is not $29xx (the shift
-- routines), with frame, $10 and the blit's source/destination; to badjsr.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local END = tonumber(os.getenv("END") or "3000")
local f, n = 0, 0
local o = io.open("badjsr.log", "w")
T = mem:install_read_tap(0x28F9, 0x291C, "bj", function(a, d)
  if a ~= PCs.value or (a ~= 0x28F9 and a ~= 0x291C) then return d end
  local t = mem:read_u8(a + 1) | (mem:read_u8(a + 2) << 8)
  if (t >> 8) ~= 0x29 and n < 200 then
    n = n + 1
    o:write(string.format("f%d JSR at %04X to %04X, $10=%d src %02X%02X dst %02X%02X\n", f, a, t, mem:read_u8(0x10),
      mem:read_u8(4), mem:read_u8(3), mem:read_u8(0x15), mem:read_u8(0x14)))
    o:flush()
  end
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
