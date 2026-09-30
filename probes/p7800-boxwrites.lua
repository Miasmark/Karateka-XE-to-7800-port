-- every write to a box of the framebuffer, frames FROM-END: pages PLO-PHI
-- (hex), page offsets OLO-OHI (hex); frame, PC, address, old and new value,
-- to boxwrites.log. Also each call of the rect fill's pass (FILLPC, hex: the
-- entry, from the symbol file) with $14/$15, X and the fill's count.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local PLO, PHI = tonumber(os.getenv("PLO"), 16), tonumber(os.getenv("PHI"), 16)
local OLO, OHI = tonumber(os.getenv("OLO"), 16), tonumber(os.getenv("OHI"), 16)
local f = 0
local o = io.open("boxwrites.log", "w")
W = mem:install_write_tap(PLO * 256 + OLO, PHI * 256 + OHI, "bw", function(a, d)
  local off = a & 0xFF
  if f >= FROM and off >= OLO and off <= OHI then
    o:write(string.format("f%d PC %04X $%04X %02X -> %02X\n", f, PCs.value, a, mem:read_u8(a), d))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
