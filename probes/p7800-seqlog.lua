-- the music sequencer each frame, FROM-END: its context while swapped out
-- (XEGS $3000-$3007, here CTX hex, default $4000: stream, header, list,
-- pattern ref), and the active flag ($2409 at ACT, default $7409) and the
-- tempo count ($2420 at TEMPO, default $7420); a line when anything but the
-- tempo count changes; to seqlog.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local CTX = tonumber(os.getenv("CTX") or "4000", 16)
local ACT = tonumber(os.getenv("ACT") or "7409", 16)
local TEMPO = tonumber(os.getenv("TEMPO") or "7420", 16)
local f, last = 0, ""
local o = io.open("seqlog.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    local s = string.format("stream %04X header %04X list %04X ref %04X act %02X",
      mem:read_u16(CTX), mem:read_u16(CTX + 2), mem:read_u16(CTX + 4), mem:read_u16(CTX + 6), mem:read_u8(ACT))
    if s ~= last then o:write(string.format("f%d %s tempo %02X\n", f, s, mem:read_u8(TEMPO))); last = s end
  end
  if f >= END then o:close(); M:exit() end
end)
