-- trace_boot2.lua -- correct tap args (addr,data,mask,pc); do NOT tap cart window
local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local OUT = os.getenv("TRACE_OUT") or "/tmp/boot_trace2.txt"
local f = io.open(OUT, "w")
f:write("F W addr<-data pc note\n")

local F = 0
emu.register_frame_done(function() F = F + 1 end)

local TAPS = {}
local ranges = {
  { name="ram_1800",  lo=0x1800, hi=0x27FF, note="RAM1800" },
  { name="zp",        lo=0x0000, hi=0x00FF, note="ZP" },
  { name="stack",     lo=0x0100, hi=0x01FF, note="STACK" },
}
for _, r in ipairs(ranges) do
  local t = mem:install_write_tap(r.lo, r.hi, "probe_boot2",
    function(addr, data, mask, pc)
      f:write(string.format("F%-4d W %04X<-%02X pc=%04X %s\n", F, addr, data, pc, r.note))
      if F > 600 and addr < 0x1800 then io.close(f); MACHINE:exit() end
    end)
  TAPS[#TAPS + 1] = t
end