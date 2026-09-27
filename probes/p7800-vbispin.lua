-- the vertical blank's confirmation: X (turns left of VBI_SPIN) when NmiVbi is
-- reached, and how often the count named an NMI that was mid-screen (the
-- fall-through after the wait, at NmiVbiWait + 8); playkey.lua drives the input; to vbispin.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, Xs = cpu.state["PC"], cpu.state["X"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local END = tonumber(os.getenv("END") or "4000")
local hist, fails, f = {}, 0, 0
T = mem:install_read_tap(0x0000, 0xFFFF, "vs", function(a, d)
  if a ~= PCs.value then return d end
  if a == S.NmiVbi then local x = Xs.value; hist[x] = (hist[x] or 0) + 1
  elseif a == S.NmiVbiWait + 8 then fails = fails + 1 end   -- LDX S_NMIVBI after the spin gave up
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("vbispin.log", "w")
    local ks = {}
    for k, _ in pairs(hist) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do o:write(string.format("X=%d left: %d times\n", k, hist[k])) end
    o:write(string.format("mid-screen corrections: %d\n", fails))
    o:close(); M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
