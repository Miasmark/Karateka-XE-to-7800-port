-- the value at ADDR at each blit start ($79E0), and every write to it, to
-- ramcheck.log (is cartridge RAM holding what was written?)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local A = tonumber(os.getenv("ADDR") or "5E86", 16)
local END = tonumber(os.getenv("END") or "200")
local f, n = 0, 0
local o = io.open("ramcheck.log", "w")
T = mem:install_read_tap(0x79E0, 0x79E0, "rc", function(a, d)
  if a == PCs.value then n = n + 1; o:write(string.format("f%d blit %d: %02X\n", f, n, mem:read_u8(A))) end
  return d end)
W = mem:install_write_tap(A, A, "rcw", function(a, d)
  o:write(string.format("f%d write %02X by %04X\n", f, d, PCs.value)); return d end)
R = mem:install_read_tap(A, A, "rcr", function(a, d)
  if n >= 3 and n <= 5 then o:write(string.format("f%d read %02X by %04X\n", f, d, PCs.value)) end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
