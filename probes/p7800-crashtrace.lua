-- the last N (default 400) instructions before the first bad fetch: a BRK, or
-- code fetched from zero page or the stack ($0000-$01FF), or from BADLO-BADHI
-- (hex, optional); PC, A X Y SP, the bank and the opcode, to crashtrace.log,
-- then MAME stops. From frame FROM (default 0) to END.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local st = cpu.state
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "2000")
local N = tonumber(os.getenv("N") or "400")
local BADLO, BADHI = tonumber(os.getenv("BADLO") or "FFFFF", 16), tonumber(os.getenv("BADHI") or "0", 16)
local ring, ri, done, f = {}, 0, false, 0
T = mem:install_read_tap(0x0000, 0xFFFF, "ct", function(a, d)
  if done or f < FROM or a ~= st["PC"].value then return d end
  ri = ri % N + 1
  ring[ri] = string.format("f%d %04X A=%02X X=%02X Y=%02X SP=%02X bank=%d op=%02X", f, a, st["A"].value, st["X"].value,
    st["Y"].value, st["SP"].value & 0xFF, mem:read_u8(S.S_BANK), d)
  if d == 0x00 or a < 0x0200 or (a >= BADLO and a <= BADHI) then
    done = true
    local o = io.open("crashtrace.log", "w")
    for k = 1, N do local e = ring[(ri + k - 1) % N + 1]; if e then o:write(e .. "\n") end end
    o:close()
    M:exit()
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("crashtrace.log", "w"); o:write("no bad fetch by frame " .. f .. "\n"); o:close()
    M:exit()
  end
end)
