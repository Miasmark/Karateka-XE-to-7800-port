-- the status bar's calls in order, per picture: $0B00 clear (C), $0B03 the
-- player's arrows (P), $0B06 the foe's (F) (on the 7800 at $9B00/$9B03/$9B06),
-- each with $07 (the buffer), $B6 and $B7, and a line per buffer flip (DPPH
-- change); from FROM to END, to statuslog.log. WITHPLAY=1: playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3600")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local NAME = {[0x9B00] = "C", [0x9B03] = "P", [0x9B06] = "F"}
local f, line, lastd = 0, {}, nil
local o = io.open("statuslog.log", "w")
T = mem:install_read_tap(0x9B00, 0x9B08, "status", function(a, d)
  if f < FROM or a ~= PCs.value or not NAME[a] then return d end
  local sp = cpu.state["SP"].value & 0xFF
  local ret = mem:read_u8(0x101 + sp) + mem:read_u8(0x101 + ((sp + 1) & 0xFF)) * 256 + 1 - 3
  line[#line + 1] = string.format("%s(%02X %d/%d @%04X)", NAME[a], mem:read_u8(ZP[7]), mem:read_u8(ZP[0xB6]), mem:read_u8(ZP[0xB7]), ret)
  return d end)
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if f >= FROM and lastd and d ~= lastd then
    o:write(string.format("f%d flip: %s\n", f, table.concat(line, " "))); line = {}
  end
  lastd = d; return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
