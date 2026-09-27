-- with playkey.lua driving the input (its env applies): from the flip
-- TRACEAT, the next TRACEN instruction fetches (PC, opcode, A X Y SP) to
-- trace.log; either machine
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local AT = tonumber(os.getenv("TRACEAT") or "652")
local N = tonumber(os.getenv("TRACEN") or "60")
local cnt = 0
local to = io.open("trace.log", "w")
TT = mem:install_read_tap(0x0000, 0xFFFF, "tf", function(a, d)
  if a ~= PCs.value or (PLAYKEY_N or 0) < AT or cnt >= N then return d end
  cnt = cnt + 1
  to:write(string.format("%04X %02X A%02X X%02X Y%02X S%02X\n", a, d, cpu.state["A"].value, cpu.state["X"].value,
    cpu.state["Y"].value, cpu.state["SP"].value & 0xFF)); to:flush()
  if cnt >= N then to:close() end
  return d end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
