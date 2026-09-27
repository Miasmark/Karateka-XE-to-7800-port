-- the story text renderer: at each record start ($0780, on the 7800 $9780) the
-- text pointer $E5/$E6 and the record's bytes; either machine; to text.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local AT = xe and 0x0780 or 0x9780
local END = tonumber(os.getenv("END") or "3000")
local f = 0
local o = io.open("text.log", "w")
T = mem:install_read_tap(AT, AT, "tp", function(a, d)
  if a ~= PCs.value then return d end
  local p = mem:read_u8(0xE5) | (mem:read_u8(0xE6) << 8)
  local s = ""
  for i = 0, 31 do
    local b = mem:read_u8(p + i)
    s = s .. string.format("%02X ", b)
    if i >= 2 and b < 0x60 then break end
  end
  o:write(string.format("f%d ptr %04X: %s\n", f, p, s)); o:flush()
  return d end)
emu.register_frame_done(function() f = f + 1; if f >= END then o:close(); M:exit() end end)
