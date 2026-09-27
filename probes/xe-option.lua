-- the original: press OPTION (CONSOL $D01F bit 2, active low) for HOLD
-- frames (default 10) at frame AT (default 400) by answering its reads;
-- screenshots every 100 frames and $D0 per 100 frames to option.log; END
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AT") or "400")
local HOLD = tonumber(os.getenv("HOLD") or "10")
local END = tonumber(os.getenv("END") or "3000")
local f = 0
local o = io.open("option.log", "w")
OPT = mem:install_read_tap(0xD01F, 0xD01F, "option", function(a, d)
  if f >= AT and f < AT + HOLD then return d & 0xFB end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f % 100 == 0 then o:write(string.format("f%d D0=%02X\n", f, mem:read_u8(0xD0))); o:flush(); M.video:snapshot() end
  if f >= END then o:close(); M:exit() end
end)
