-- experiment: MARIA DMA forced off (every CTRL write gets DMA-off bits), to
-- measure how many CPU cycles the display costs; chains pchist.lua
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
if os.getenv("NODMA") then
  C = mem:install_write_tap(0x3C, 0x3C, "nodma", function(a, d) return d | 0x60 end)
end
dofile(os.getenv("PROBES") .. "/pchist.lua")
