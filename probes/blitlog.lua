-- every sprite blit's source, at $29E0 (just after the source bank is
-- chosen): frame, source pointer, and the first 12 bytes read through it
-- (header then data). MACHINE=xe for the original ($29E0, zp $03/$04),
-- otherwise the 7800 build (engine at $7000+, zp from ZP3/ZP4, default $C9/$CA).
-- ZPDUMP=1 adds the game's zero page $00-$3F (on the 7800 through the build's
-- map, ZPMAP = work/karateka7800.zp). To blits.log; stops after END frames or
-- LIMIT blits.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local AT = xe and 0x29E0 or 0x79E0
local Z3 = xe and 0x03 or tonumber(os.getenv("ZP3") or "C9", 16)
local Z4 = xe and 0x04 or tonumber(os.getenv("ZP4") or "CA", 16)
local END = tonumber(os.getenv("END") or "600")
local LIMIT = tonumber(os.getenv("LIMIT") or "5000")
local f, n = 0, 0
local ZMAP = {}
for z = 0, 255 do ZMAP[z] = z end
if not xe and os.getenv("ZPMAP") then
  for line in io.lines(os.getenv("ZPMAP")) do
    local z, t = line:match("^(%x+) (%x+)")
    if z then ZMAP[tonumber(z, 16)] = tonumber(t, 16) end
  end
end
local ZPDUMP = os.getenv("ZPDUMP")
local o = io.open("blits.log", "w")
T = mem:install_read_tap(AT, AT, "blit", function(a, d)
  if a == PCs.value and n < LIMIT then
    n = n + 1
    local p = mem:read_u8(Z3) | (mem:read_u8(Z4) << 8)
    local s = ""
    for i = 0, 11 do s = s .. string.format(" %02X", mem:read_u8(p + i)) end
    if ZPDUMP then
      s = s .. " |"
      for z = 0, 0x3F do s = s .. string.format(" %02X", mem:read_u8(ZMAP[z])) end
    end
    o:write(string.format("f%d k%d %04X%s\n", f, PLAYKEY_N or 0, p, s))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
-- WITHPLAY=1: drive the input with playkey.lua (its env applies); each line
-- then carries its flip number (k)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
