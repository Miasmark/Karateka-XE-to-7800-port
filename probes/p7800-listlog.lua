-- per frame from FROM to END: the list the game asks for (S_DLIST), the DLL
-- MARIA was last pointed at (DPPH/DPPL writes), each buffer's built list
-- (S_DLIST_A/B), and how many times BuildDll ran and in which frame line;
-- to listlog.log. No input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
-- the scanline, estimated: emulated time since the last frame end, in
-- lines of 1 / (59.92 x 263) s (this MAME's screen has no vpos)
local t0 = 0
local screen = {vpos = function() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end}
local f = 0
local dpph, dppl = 0, 0
local ev = {}
DH = mem:install_write_tap(0x002C, 0x002C, "dh", function(a, d)
  dpph = d
  if f >= FROM then ev[#ev + 1] = string.format("DPPH<-%02X@%d", d, screen.vpos()) end
  return d end)
DL = mem:install_write_tap(0x0030, 0x0030, "dl", function(a, d) dppl = d; return d end)
local BUILD = S.BuildDll
T = mem:install_read_tap(BUILD, BUILD, "bd", function(a, d)
  if a == cpu.state["PC"].value and f >= FROM then
    ev[#ev + 1] = string.format("Build(idx %d)@%d", mem:read_u8(S.S_DLIDX), screen.vpos())
  end
  return d end)
local o = io.open("listlog.log", "w")
local function w16(a) return mem:read_u8(a) + 256 * mem:read_u8(a + 1) end
emu.register_frame_done(function()
  t0 = M.time:as_double()
  f = f + 1
  if f >= FROM then
    o:write(string.format("f%d want $%04X shown DLL $%02X%02X  A=$%04X B=$%04X  %s\n", f, w16(S.S_DLIST), dpph, dppl,
      w16(S.S_DLIST_A), w16(S.S_DLIST_B), table.concat(ev, " ")))
    ev = {}
  end
  if f >= END then o:close(); M:exit() end
end)

if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
