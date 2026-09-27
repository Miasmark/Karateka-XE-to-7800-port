-- writes to a RAM range (WATCH = "7160-716F"): frame, PC, address, value, bank,
-- and the system label of the PC; stops after END frames or LIMIT writes
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local lo, hi = (os.getenv("WATCH") or "7160-716F"):match("(%x+)-(%x+)")
lo, hi = tonumber(lo, 16), tonumber(hi, 16)
local END = tonumber(os.getenv("END") or "300")
local LIMIT = tonumber(os.getenv("LIMIT") or "2000")
local f, n = 0, 0
local o = io.open("watch.log", "w")
W = mem:install_write_tap(lo, hi, "watch", function(a, d)
  if n < LIMIT then
    n = n + 1
    local pc = cpu.state["PC"].value
    o:write(string.format("f%d PC=%04X %04X<-%02X b%d %s\n", f, pc, a, d, mem:read_u8(SYM_ADDR.S_BANK), SYM_NAME[pc] or ""))
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
