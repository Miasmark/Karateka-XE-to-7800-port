-- writes to the TIA's sound registers (AUDC0-AUDV1, $15-$1A) from FROM to
-- END: per PC the count and values seen, and per frame how many writes;
-- a line per frame (register=value in order, and the PC when it changes) to
-- tiawrites.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local f, line, lastpc = 0, {}, nil
local o = io.open("tiawrites.log", "w")
local NAMES = {[0x15] = "C0", [0x16] = "C1", [0x17] = "F0", [0x18] = "F1", [0x19] = "V0", [0x1A] = "V1"}
W = mem:install_write_tap(0x15, 0x1A, "tia", function(a, d)
  if f >= FROM then
    local pc = PCs.value
    if pc ~= lastpc then line[#line + 1] = string.format("@%04X", pc); lastpc = pc end
    line[#line + 1] = string.format("%s=%02X", NAMES[a], d)
  end
  return d end)
emu.register_frame_done(function()
  if f >= FROM then o:write(string.format("f%d %s\n", f, table.concat(line, " "))) end
  line, lastpc = {}, nil
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
