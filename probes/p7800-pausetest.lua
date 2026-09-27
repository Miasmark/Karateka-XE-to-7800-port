-- the 7800 Pause button: playkey.lua drives the game into scene 1; Pause is
-- pressed for 6 frames at P1 and again at P2; the flip count every 50
-- frames goes to pause.log (it should stop between the presses)
local M = manager.machine
local P1 = tonumber(os.getenv("P1") or "3500")
local P2 = tonumber(os.getenv("P2") or "4000")
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local po = io.open("pause.log", "w")
local fr = 0
emu.register_frame_done(function()
  fr = fr + 1
  local on = (fr >= P1 and fr < P1 + 6) or (fr >= P2 and fr < P2 + 6)
  fields["Pause"]:set_value(on and 1 or 0)
  if fr % 50 == 0 then po:write(string.format("f%d flips %d\n", fr, PLAYKEY_N or 0)); po:flush() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
