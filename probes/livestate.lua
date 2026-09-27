-- livestate.lua -- read PC register + key memory each frame after boot
local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local OUT = "/tmp/livestate.txt"
local f = io.open(OUT, "w")
f:write("F PC regs mem\n")

local F = 0
emu.register_frame_done(function()
  F = F + 1
  if F < 8 or (F >= 8 and F <= 15) or (F % 20 == 0 and F <= 300) then
    local pc = "?"
    pcall(function()
      local st = cpu.state
      pc = string.format("%04X", st["PC"].value)
    end)
    local m8000 = mem:read_u8(0x8000)
    local m8116 = mem:read_u8(0x8116) -- scene-code internal ref target from disasm
    local m1169 = mem:read_u8(0x1169)
    local m1800 = mem:read_u8(0x1800)
    local m1000 = mem:read_u8(0x1000)
    f:write(string.format("F%-4d PC=%s [8000]=%02X [8116]=%02X [1169]=%02X [1800]=%02X [1000]=%02X\n",
      F, pc, m8000, m8116, m1169, m1800, m1000))
    f:flush()
  end
  if F >= 300 then MACHINE:exit() end
end)