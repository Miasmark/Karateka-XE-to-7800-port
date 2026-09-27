-- every draw call from frame FROM to END, in order, with the picture it went
-- into: blitter A/B/C by source, column ($05), top row ($06), mode ($0F),
-- shift ($10), and the JSR it came from, then its true size (after the bank
-- switch; the header read at entry may be another bank's); fills by rectangle.
-- To blitlog.log. WITHPLAY=1: playkey.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3100")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local ENTRY = {[0x784E] = "A", [0x7B82] = "B", [0x7B8B] = "C", [0x7CCD] = "fill", [0x7D03] = "pattern", [0x780F] = "clear"}
local f, pic = 0, 0
local o = io.open("blitlog.log", "w")
T = mem:install_read_tap(0x7800, 0x7D10, "bl", function(a, d)
  if f < FROM or a ~= PCs.value then return d end
  if a == 0x7857 or a == 0x7A04 then       -- past the header (bank in): the true size
    o:write(string.format("f%d p%d   size %dx%d col %d\n", f, pic, z(0x0D), z(0x0E), z(0x05)))
    return d
  end
  local k = ENTRY[a]
  if k then
    local sp = SPs.value & 0xFF
    local ret = mem:read_u8(0x101 + sp) + 256 * mem:read_u8(0x102 + sp) - 2
    if #k == 1 then
      local src = z(0x04) * 256 + z(0x03)
      o:write(string.format("f%d p%d blit%s $%04X %dx%d col %d row %d mode %02X shift %d buf %02X from $%04X\n", f, pic, k, src,
        mem:read_u8(src), mem:read_u8(src + 1), z(0x05), z(0x06), z(0x0F), z(0x10), z(0x07), ret))
    elseif k == "clear" then
      o:write(string.format("f%d p%d clear\n", f, pic))
    else
      o:write(string.format("f%d p%d %s cols %d-%d rows %d-%d buf %02X from $%04X\n", f, pic, k, z(0x05), z(0x09), z(0x06), z(0x08), z(0x07), ret))
    end
  end
  return d end)
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) if f >= FROM then pic = pic + 1; o:write(string.format("f%d flip -> %02X\n", f, d)) end; return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
