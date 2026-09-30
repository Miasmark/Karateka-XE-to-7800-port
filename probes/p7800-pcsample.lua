-- where the CPU is: every instruction fetch during frames AT to AT+N, counted
-- by PC (the top 30), with the system symbols; to pcsample.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local AT = tonumber(os.getenv("AT") or "400")
local N = tonumber(os.getenv("N") or "1")
local f, cnt = 0, {}
T = mem:install_read_tap(0x0000, 0xFFFF, "pcs", function(a, d)
  if f >= AT and f < AT + N and a == PCs.value then cnt[a] = (cnt[a] or 0) + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= AT + N then
    local l = {}
    for a, n in pairs(cnt) do l[#l + 1] = {a, n} end
    table.sort(l, function(x, y) return x[2] > y[2] end)
    local o = io.open("pcsample.log", "w")
    for i = 1, math.min(30, #l) do
      local a = l[i][1]
      local nm, best = "", -1
      for k, v in pairs(SYM_ADDR) do if v <= a and v > best and a - v < 0x100 then best, nm = v, k end end
      o:write(string.format("%04X %6d  %s+%d\n", a, l[i][2], nm, best >= 0 and a - best or 0))
    end
    o:close(); M:exit()
  end
end)

if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
