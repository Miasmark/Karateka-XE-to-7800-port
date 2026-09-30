-- the original's tune starts ($2422, tune in A) with frame and caller, from
-- FROM to END, while a recording plays (CHEAT: the script it was recorded
-- with); to tunelog.log (port/runxe.sh)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "6000")
local f = 0
local o = io.open("tunelog.log", "w")
TX = mem:install_read_tap(0x2422, 0x2422, "tune", function(a, d)
  if f >= FROM and a == cpu.state["PC"].value then
    local sp = cpu.state["SP"].value & 0xFF
    local r1 = mem:read_u8(0x101 + sp) + mem:read_u8(0x101 + ((sp + 1) & 0xFF)) * 256
    o:write(string.format("f%d tune %d  from $%04X\n", f, cpu.state["A"].value, r1 + 1)); o:flush()
  end
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
