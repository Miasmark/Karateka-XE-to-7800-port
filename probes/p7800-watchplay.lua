-- p7800-watch.lua's write log (WATCH, FROM frame) with playkey.lua driving
-- the input (its env applies); to watch.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local lo, hi = (os.getenv("WATCH") or "78FA-78FB"):match("(%x+)-(%x+)")
lo, hi = tonumber(lo, 16), tonumber(hi, 16)
local FROM = tonumber(os.getenv("FROM") or "0")
local LIMIT = tonumber(os.getenv("LIMIT") or "3000")
local fr, cnt = 0, 0
local wo = io.open("watch.log", "w")
WW = mem:install_write_tap(lo, hi, "wp", function(a, d)
  if fr >= FROM and cnt < LIMIT then
    cnt = cnt + 1
    local pc = cpu.state["PC"].value
    wo:write(string.format("f%d PC=%04X %04X<-%02X b%d %s\n", fr, pc, a, d, mem:read_u8(SYM_ADDR.S_BANK), SYM_NAME[pc] or ""))
    wo:flush()
  end
  return d end)
emu.register_frame_done(function() fr = fr + 1 end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
