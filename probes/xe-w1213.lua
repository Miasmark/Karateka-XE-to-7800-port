-- the original: writes to $12/$13 from frame FROM to END with PC and SP, and
-- whether the copy loop ($ADCC-$ADE4) was interrupted to make them; to w1213.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "4675")
local END = tonumber(os.getenv("END") or "4700")
local f = 0
local o = io.open("w1213.log", "w")
W = mem:install_write_tap(0x0012, 0x0013, "w", function(a, d)
  if f >= FROM then
    local sp = cpu.state["SP"].value & 0xFF
    o:write(string.format("f%d PC=%04X $%02X<-%02X SP=%02X\n", f, cpu.state["PC"].value, a, d, sp))
  end
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
