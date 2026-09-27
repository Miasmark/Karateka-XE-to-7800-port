-- how much of each frame the game spends waiting: fetches of the flip wait
-- loops (LOOPS, hex, comma-separated; each turn LDA abs + BMI = 7 cycles),
-- as cycles per frame, per BLOCK frames (default 100) from FROM to END, with
-- the scene; to idle.log. WITHPLAY=1: playkey drives the input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "6000")
local BLOCK = tonumber(os.getenv("BLOCK") or "100")
local loops = {}
for h in (os.getenv("LOOPS") or ""):gmatch("%x+") do loops[tonumber(h, 16)] = true end
local f, turns, nf = 0, 0, 0
local o = io.open("idle.log", "w")
T = mem:install_read_tap(0xC000, 0xFFFF, "idle", function(a, d)
  if f >= FROM and loops[a] and a == cpu.state["PC"].value then turns = turns + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > FROM then
    nf = nf + 1
    if nf == BLOCK then
      o:write(string.format("f%d scene %d: waiting %.0f cycles a frame (%.0f%% of 29,868)\n",
        f, mem:read_u8(0xD0), turns * 7 / BLOCK, turns * 7 / BLOCK / 298.68))
      o:flush(); turns, nf = 0, 0
    end
  end
  if f >= END then o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
