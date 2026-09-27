-- both framebuffers at frame AT, to fb<AT>.bin (A then B, $17E8 bytes each):
-- MACHINE=xe reads the original's ($4808, $3010), otherwise the 7800 build's
-- ($5808, $4010)
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AT") or "300")
local xe = os.getenv("MACHINE") == "xe"
local A, B = xe and 0x4808 or 0x5808, xe and 0x3010 or 0x4010
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local o = io.open(string.format("fb%d.bin", AT), "wb")
    for _, base in ipairs({A, B}) do
      local t = {}
      for i = 0, 0x17E7 do t[#t + 1] = string.char(mem:read_u8(base + i)) end
      o:write(table.concat(t))
    end
    o:close(); M:exit()
  end
end)
