-- (p7800-blitsetup.lua) each call of the game's blitter setup (engine2 $2A04, PC AT hex, default
-- $7A04) and its state after clipping ($2A6D, PC AT2, default $7A6D), frames
-- FROM-END: the XEGS zero page bytes in ZPS (hex list), read through the
-- build's zero-page map (ZPMAP), and the row (engine2 $2DA1 at ROWAT,
-- default $7DA1); to blitsetup.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local AT = tonumber(os.getenv("AT") or "7A04", 16)
local AT2 = tonumber(os.getenv("AT2") or "7A6D", 16)
local ROWAT = tonumber(os.getenv("ROWAT") or "7DA1", 16)
local map = {}
for l in io.lines(os.getenv("ZPMAP")) do
  local x, a = l:match("(%x+) (%x+)")
  if x then map[tonumber(x, 16)] = tonumber(a, 16) end
end
local zps = {}
for h in (os.getenv("ZPS") or "03 04 05 0D 0E 0F 10 1D 1E 1F 16"):gmatch("%x+") do zps[#zps + 1] = tonumber(h, 16) end
local f = 0
local o = io.open("blitsetup.log", "w")
local function state(tag)
  local s = string.format("f%d %s row=%02X", f, tag, mem:read_u8(ROWAT))
  for _, z in ipairs(zps) do s = s .. string.format(" %02X=%02X", z, mem:read_u8(map[z])) end
  o:write(s .. "\n")
end
T = mem:install_read_tap(math.min(AT, AT2), math.max(AT, AT2), "bl", function(a, d)
  if f >= FROM and a == PCs.value then
    if a == AT then state("in ") elseif a == AT2 then state("clp") end
  end
  return d end)
-- WRITES=1: also every framebuffer write by the blitter's stores (hex list
-- WPCS, default $7B12 $7B3E), as row/byte in the new layout
local WP = {}
for h in (os.getenv("WPCS") or "7B12 7B3E"):gmatch("%x+") do WP[tonumber(h, 16)] = true end
if os.getenv("WRITES") then
  W = mem:install_write_tap(0x4010, 0x72FF, "bw", function(a, d)
    local pc = PCs.value
    if f >= FROM and WP[pc] then
      local lo, pg = a & 0xFF, a >> 8
      local col = (lo - 16) // 40
      o:write(string.format("   %04X $%04X buf %s row %d byte %d = %02X\n", pc, a, col < 3 and "A" or "B",
        (col % 3) * 51 + (0x72 - pg), (lo - 16) % 40, d))
    end
    return d end)
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
