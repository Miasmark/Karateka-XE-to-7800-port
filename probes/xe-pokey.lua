-- the original's POKEY: every write to $D200-$D208 (AUDF1-4, AUDC1-4, AUDCTL)
-- as "frame flip reg value pc", to pokey.log. With WITHPLAY=1, playkey.lua
-- drives the input (its env applies, MACHINE=xe); otherwise no input and
-- END frames (default 3000)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local po = io.open("pokey.log", "w")
local fr = 0
PW = mem:install_write_tap(0xD200, 0xD208, "pokey", function(a, d)
  po:write(string.format("%d %d %X %02X %04X\n", fr, PLAYKEY_N or 0, a - 0xD200, d, cpu.state["PC"].value))
  return d end)
local END = tonumber(os.getenv("END") or "3000")
emu.register_frame_done(function()
  fr = fr + 1
  if not os.getenv("WITHPLAY") and fr >= END then po:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
