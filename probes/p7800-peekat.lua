-- memory LO-HI (hex) at the PC AT (hex, first time from frame FROM on), to
-- peekat.log as hex, 16 bytes a line
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local AT = tonumber(os.getenv("AT"), 16)
local LO, HI = tonumber(os.getenv("LO"), 16), tonumber(os.getenv("HI"), 16)
local f, done = 0, false
-- SRC (hex): only when the blitter's source pointer (XEGS $03/$04, here $C9) is this
local SRC = os.getenv("SRC") and tonumber(os.getenv("SRC"), 16)
T = mem:install_read_tap(AT, AT, "pk", function(a, d)
  if not done and f >= FROM and a == PCs.value and (not SRC or mem:read_u16(0xC9) == SRC) then
    done = true
    local o = io.open("peekat.log", "w")
    for b = LO, HI, 16 do
      local s = string.format("%04X:", b)
      for i = 0, 15 do if b + i <= HI then s = s .. string.format(" %02X", mem:read_u8(b + i)) end end
      o:write(s .. "\n")
    end
    o:close()
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END or done then M:exit() end
end)
