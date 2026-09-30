-- each frame FROM-END: the POKEY shadow (S_POKEY at SP hex, 8 bytes: voice 0
-- AUDF1 AUDC1 AUDF2 AUDC2, voice 1 AUDF3 AUDC3 AUDF4 AUDC4) and the TIA
-- sound registers as last written (C0 C1 F0 F1 V0 V1); to voicelog.log,
-- a line when anything changes
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local SP = tonumber(os.getenv("SP") or "1E17", 16)
local tia = {0, 0, 0, 0, 0, 0}
W = mem:install_write_tap(0x15, 0x1A, "tia", function(a, d) tia[a - 0x14] = d; return d end)
local f, last = 0, ""
local o = io.open("voicelog.log", "w")
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    local s = ""
    for i = 0, 7 do s = s .. string.format("%02X ", mem:read_u8(SP + i)) end
    s = s .. string.format("| %02X %02X %02X %02X %02X %02X", tia[1], tia[2], tia[3], tia[4], tia[5], tia[6])
    if s ~= last then o:write(string.format("f%d %s\n", f, s)); last = s end
  end
  if f >= END then o:close(); M:exit() end
end)
