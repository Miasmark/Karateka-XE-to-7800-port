-- what the game's DLI handler ($7026 to its RTI at $7039) reads from the
-- banked window $8000-$BFFF: data reads (not fetches) while it runs, by
-- address range and the bank then selected; to dlireads.log at END.
-- WITHPLAY=1: playkey drives the input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "15000")
local f, inside, runs, reads = 0, false, 0, {}
local total = 0
T1 = mem:install_read_tap(0x7026, 0x7039, "dlipc", function(a, d)
  if a ~= PCs.value then return d end
  if a == 0x7026 then inside = true; runs = runs + 1 end
  if a == 0x7039 then inside = false end
  return d end)
T2 = mem:install_read_tap(0x8000, 0xBFFF, "dliread", function(a, d)
  if not inside or a == PCs.value then return d end
  local k = string.format("$%02Xxx bank %d (PC %04X)", a >> 8, mem:read_u8(S.S_BANK), PCs.value)
  reads[k] = (reads[k] or 0) + 1
  total = total + 1
  return d end)
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("dlireads.log", "w")
  o:write(string.format("frames %d: %d DLI handler runs, %d reads from $8000-$BFFF\n", f, runs, total))
  local t = {}
  for k, n in pairs(reads) do t[#t + 1] = {k, n} end
  table.sort(t, function(x, y) return x[2] > y[2] end)
  for i = 1, math.min(30, #t) do o:write(string.format("  %s: %d\n", t[i][1], t[i][2])) end
  o:close()
end
STOP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then report(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
