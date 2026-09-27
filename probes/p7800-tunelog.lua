-- the tunes the game starts ($2422, the port's Sound: A), in order with the
-- frame and the caller, from FROM to END; to tunelog.log. WITHPLAY=1.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local f = 0
local o = io.open("tunelog.log", "w")
TT = mem:install_read_tap(SYM_ADDR.Sound, SYM_ADDR.Sound, "tune", function(a, d)
  if f >= FROM and a == cpu.state["PC"].value then
    local sp = cpu.state["SP"].value & 0xFF
    local r1 = mem:read_u8(0x101 + sp) + mem:read_u8(0x101 + ((sp + 1) & 0xFF)) * 256
    local r2 = mem:read_u8(0x103 + sp) + mem:read_u8(0x101 + ((sp + 3) & 0xFF)) * 256
    o:write(string.format("f%d tune %d  from $%04X/$%04X\n", f, cpu.state["A"].value, r1 + 1, r2 + 1)); o:flush()
  end
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
