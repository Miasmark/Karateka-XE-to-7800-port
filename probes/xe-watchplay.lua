-- the original: writes to WATCH (hex range) from frame FROM, with
-- playkey.lua driving the input (its env applies; MACHINE=xe); to watch.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local lo, hi = (os.getenv("WATCH") or "6000-60FF"):match("(%x+)-(%x+)")
lo, hi = tonumber(lo, 16), tonumber(hi, 16)
local FROM = tonumber(os.getenv("FROM") or "0")
local LIMIT = tonumber(os.getenv("LIMIT") or "3000")
local fr, cnt = 0, 0
local wo = io.open("watch.log", "w")
WW = mem:install_write_tap(lo, hi, "wp", function(a, d)
  if fr >= FROM and cnt < LIMIT then
    cnt = cnt + 1
    wo:write(string.format("f%d PC=%04X %04X<-%02X\n", fr, cpu.state["PC"].value, a, d)); wo:flush()
  end
  return d end)
emu.register_frame_done(function() fr = fr + 1 end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
