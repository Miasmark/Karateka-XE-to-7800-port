-- press fire for 8 frames at frame AT (either machine); log each frame's sound
-- state to press.log: the original's POKEY voices (from its registers as
-- written) or the port's TIA volumes and the POKEY shadow; stop at END
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local xe = os.getenv("MACHINE") == "xe"
local AT = tonumber(os.getenv("AT") or "300")
local END = tonumber(os.getenv("END") or "900")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local regs = {}
for i = 0, 8 do regs[i] = 0 end
local tia = {[0x15] = 0, [0x16] = 0, [0x17] = 0, [0x18] = 0, [0x19] = 0, [0x1A] = 0}
if xe then
  P = mem:install_write_tap(0xD200, 0xD208, "pk", function(a, d) regs[a - 0xD200] = d; return d end)
else
  P = mem:install_write_tap(0x0015, 0x001A, "tia", function(a, d) tia[a] = d; return d end)
end
local o = io.open("press.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  fields["P1 Button 1"]:set_value((f >= AT and f < AT + 8) and 1 or 0)
  if xe then
    o:write(string.format("f%d v0 %X/%04X v1 %X/%04X D0=%02X\n", f, regs[3] & 15, regs[2] * 256 + regs[0],
      regs[7] & 15, regs[6] * 256 + regs[4], mem:read_u8(0xD0)))
  else
    o:write(string.format("f%d v0 %X/%X:%02d v1 %X/%X:%02d D0=%02X\n", f, tia[0x19], tia[0x15], tia[0x17],
      tia[0x1A], tia[0x16], tia[0x18], mem:read_u8(0xD0)))
  end
  if f >= END then o:close(); M:exit() end
end)
