-- who writes the POKEY shadow ($1E17-$1E1F: AUDF1..AUDCTL): per PC, the
-- registers and values written, from FROM to END (frames counted from the
-- start, or from a state load with MODE=feed via p7800-inputlog.lua loaded
-- first); to pokeywriters.log at the end. WITHPLAY=1: playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local f = 0
local by = {}
W = mem:install_write_tap(0x1E17, 0x1E1F, "pk", function(a, d)
  if f >= FROM then
    local k = string.format("PC %04X reg %d", cpu.state["PC"].value, a - 0x1E17)
    local e = by[k] or {n = 0, vals = {}}
    e.n = e.n + 1; e.vals[d] = (e.vals[d] or 0) + 1; by[k] = e
  end
  return d end)
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("pokeywriters.log", "w")
  local ks = {}
  for k in pairs(by) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do
    local e, vs = by[k], {}
    for v, n in pairs(e.vals) do vs[#vs + 1] = string.format("%02X:%d", v, n) end
    table.sort(vs)
    o:write(string.format("%s: %d writes  %s\n", k, e.n, table.concat(vs, " ", 1, math.min(8, #vs))))
  end
  o:close()
end
STOPP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function() f = f + 1; if f >= END then report(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
