-- a7800_state.lua -- dump MARIA / RIOT / RAM state at selected frames
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM = tonumber(os.getenv("A7800_SNAP_FROM") or "1")
local TO   = tonumber(os.getenv("A7800_SNAP_TO") or "60")
local STEP = tonumber(os.getenv("A7800_SNAP_STEP") or "20")
local F = 0

local function rd(a) return mem:read_u8(a) end

emu.register_frame_done(function()
  F = F + 1
  if F < FROM or F > TO or ((F - FROM) % STEP) ~= 0 then
    if F > TO then M:exit() end
    return
  end
  local maria = {}
  for a = 0, 0x2E do maria[a] = rd(a) end
  print(string.format("FRAME %d", F))
  print("MARIA: CTRL=%02X INPT=%02X DPPL=%02X DPPH=%02X WSYNC=%02X",
    maria[0], maria[3], maria[5], maria[4], maria[0x22])
  print("  regs:", string.format([[
    00_CTRL %02X  01_snv %02X  02_opy %02X  03_inpt %02X
    04_dpph %02X  05_dppl %02X  06_chbase %02X  07_backgr %02X
    08_RAM? %02X  09_??? %02X  0A_offs %02X  0B_obsbp %02X
    0C_MAP? %02X  0D_??? %02X  0E_??? %02X  0F_??? %02X]], maria[0],rd(1),rd(2),maria[3],
    maria[4],maria[5],rd(6),rd(7),rd(8),rd(9),rd(0xA),rd(0xB),rd(0xC),rd(0xD),rd(0xE),rd(0xF)))
  print("RIOT: SWCHA=%02X SWCHB=%02X INPT4=%02X INPT5=%02X", rd(0x280),rd(0x281),rd(0x0C),rd(0x0D))
  local r = {}
  for a = 0x1800, 0x180F do r[a] = rd(a) end
  print("RAM $1800-$180F:", string.format("%s", table.concat(r)))
  local v = {}
  for a = 0x1FFF, 0x200E do v[a] = rd(a) end
  print("RAM $1FFF-$200E:", string.format("%s", table.concat(v)))
  if F > TO then M:exit() end
end)