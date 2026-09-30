-- the POKEY shadow (S_POKEY at SP hex, registers 0-8: AUDF1-AUDC4, AUDCTL)
-- as the game's driver writes it, frames FROM-END, in probes/xe-pokey.lua's
-- log format ("frame 0 reg value 0", a line per changed register) for
-- port/sndconv.py: the original's sound (its POKEY model) against the TIA's
-- from the same notes; to shadow.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local SP = tonumber(os.getenv("SP") or "1E17", 16)
local f, last = 0, {}
local o = io.open("shadow.log", "w")
emu.register_frame_done(function()
  if f >= FROM then
    for r = 0, 8 do
      local v = mem:read_u8(SP + r)
      if v ~= last[r] then o:write(string.format("%d 0 %X %02X 0\n", f, r, v)); last[r] = v end
    end
  end
  f = f + 1
  if f >= END then o:close(); M:exit() end
end)
