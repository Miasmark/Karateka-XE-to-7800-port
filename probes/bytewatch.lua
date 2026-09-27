-- every write to ADDR (hex) with frame, PC and value, to bytewatch.log; for
-- either machine (no symbols needed); stops after END frames
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local A = tonumber(os.getenv("ADDR"), 16)
local A2 = tonumber(os.getenv("ADDR2") or os.getenv("ADDR"), 16)
local END = tonumber(os.getenv("END") or "600")
local f = 0
local o = io.open("bytewatch.log", "w")
W = mem:install_write_tap(A, A2, "bw", function(a, d)
  o:write(string.format("f%d PC=%04X %04X<-%02X\n", f, cpu.state["PC"].value, a, d))
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
