-- per frame from FROM to END: the game's POKEY voices as it writes them
-- (the original: its registers; the port: the shadow S_POKEY, $1E17) as
-- AUDCTL, then per channel AUDC/AUDF, and on the port the TIA's AUDV/AUDC/
-- AUDF for both channels; with $D0; to sound.log. A screenshot every SNAP
-- frames (default 200). MACHINE=xe for the original; CHEAT: a script to load
-- first (the one a recording was made with).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local xe = os.getenv("MACHINE") == "xe"
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "60000")
local SNAP = tonumber(os.getenv("SNAP") or "200")
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local pk = {}
for i = 0, 8 do pk[i] = 0 end
local tia = {[0x15] = 0, [0x16] = 0, [0x17] = 0, [0x18] = 0, [0x19] = 0, [0x1A] = 0}
if xe then
  P = mem:install_write_tap(0xD200, 0xD208, "pk", function(a, d) pk[a - 0xD200] = d; return d end)
else
  P = mem:install_write_tap(0x0015, 0x001A, "tia", function(a, d) tia[a] = d; return d end)
end
local o = io.open("sound.log", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    if not xe then for i = 0, 8 do pk[i] = mem:read_u8(0x1E17 + i) end end
    local line = string.format("f%d D0=%02X hp %02X/%02X ctl %02X  c1 %02X/%02X c2 %02X/%02X c3 %02X/%02X c4 %02X/%02X", f,
      mem:read_u8(0xD0), mem:read_u8(0xB6), mem:read_u8(0xB7), pk[8], pk[1], pk[0], pk[3], pk[2], pk[5], pk[4], pk[7], pk[6])
    if not xe then
      line = line .. string.format("  tia v%X c%X f%02d  v%X c%X f%02d", tia[0x19], tia[0x15], tia[0x17], tia[0x1A], tia[0x16], tia[0x18])
    end
    o:write(line .. "\n")
    if (f - FROM) % SNAP == 0 then M.video:snapshot() end
  end
  if f >= END then o:close(); M:exit() end
end)
