-- bootp.lua -- with -debug: print real PC each frame + bytes at key addrs
local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]
local d = cpu:debug()

local OUT = "/tmp/bootp.txt"
local f = io.open(OUT, "w")
f:write("bootp probe\n")

local F = 0
emu.register_frame_done(function()
  F = F + 1
  local pc = d:pc()
  if F <= 120 then
    local r284E = mem:read_u8(0x284E)
    local r1800 = mem:read_u8(0x1800)
    f:write(string.format("F%-4d PC=%04X RAM[1800]=%02X RAM[284E]=%02X\n", F, pc, r1800, r284E))
  end
  if F == 120 then io.close(f); MACHINE:exit() end
end)