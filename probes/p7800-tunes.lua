-- the tune numbers the game starts ($2422, the port's Sound: A), counted, to
-- tunes.log when MAME stops; with p7800-inputlog.lua MODE=feed
dofile(os.getenv("PROBES") .. "/p7800-inputlog.lua")
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local count = {}
TT = mem:install_read_tap(SYM_ADDR.Sound, SYM_ADDR.Sound, "tune", function(a, d)
  if a == cpu.state["PC"].value then local t = cpu.state["A"].value; count[t] = (count[t] or 0) + 1 end
  return d end)
STOPT = emu.add_machine_stop_notifier(function()
  local o = io.open("tunes.log", "w")
  local ks = {}
  for k in pairs(count) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do o:write(string.format("tune %d: %d starts\n", k, count[k])) end
  o:close()
end)
