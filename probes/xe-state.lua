-- the original with no input: PC, SP, $D0 and the display list every 100
-- frames from FROM to END; to state.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "4000")
local END = tonumber(os.getenv("END") or "9000")
local f = 0
local o = io.open("state.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM and f % 100 == 0 then
    o:write(string.format("f%d PC=%04X SP=%02X D0=%02X SDLST=%02X%02X COLBK=%02X\n", f, cpu.state["PC"].value,
      cpu.state["SP"].value & 0xFF, mem:read_u8(0xD0), mem:read_u8(0x231), mem:read_u8(0x230), mem:read_u8(0x2C8)))
    o:flush()
  end
  if f >= END then o:close(); M:exit() end
end)
