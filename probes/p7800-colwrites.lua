-- per frame from FROM to END: every write to MARIA's colour registers
-- ($20-$3F except the DMA/list ones) at scanlines LINE0-LINE1, with the line,
-- the register, the value and the PC; to colwrites.log. No input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
-- the scanline, estimated: emulated time since the last frame end, in
-- lines of 1 / (59.92 x 263) s (this MAME's screen has no vpos)
local t0 = 0
local screen = {vpos = function() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end}
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local L0, L1 = tonumber(os.getenv("LINE0") or "150"), tonumber(os.getenv("LINE1") or "262")
local f = 0
local ev = {}
local skip = {[0x24] = true}   -- WSYNC only (ALL=1 logs the list and mode registers too)
if not os.getenv("ALL") then skip = {[0x2C] = true, [0x30] = true, [0x34] = true, [0x38] = true, [0x3C] = true, [0x24] = true, [0x28] = true} end
T = mem:install_write_tap(0x0020, 0x003F, "col", function(a, d)
  if f >= FROM and not skip[a] then
    local v = screen.vpos()
    if v >= L0 and v <= L1 then
      ev[#ev + 1] = string.format("%d:%02X=%02X(%04X)", v, a, d, cpu.state["PC"].value)
    end
  end
  return d end)
local o = io.open("colwrites.log", "w")
emu.register_frame_done(function()
  t0 = M.time:as_double()
  f = f + 1
  if f >= FROM and os.getenv("SNAP") then M.video:snapshot() end
  if f >= FROM then o:write(string.format("f%d %s\n", f, table.concat(ev, " "))); ev = {} end
  if f >= END then o:close(); M:exit() end
end)
