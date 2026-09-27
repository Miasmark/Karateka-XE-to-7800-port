-- cycles spent inside the vertical blank (S_INVBI set) per frame, split by
-- where the PC is: system routines by name, game code by page; playkey.lua
-- drives the input. Averages over FROM..END to vbicost.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3300")
local CYC = {}
do
  local t = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
  for i, c in ipairs(t) do CYC[i] = c end
end
local names = {}
for a, n in pairs(SYM_NAME) do if a >= 0xE000 and a < 0xF800 and not n:match("^S_") then names[#names + 1] = {a, n} end end
table.sort(names, function(x, y) return x[1] < y[1] end)
local function where(a)
  if a < 0xE000 or a >= 0xF800 then return string.format("game %02Xxx", a >> 8) end
  local lo, hi, best = 1, #names, "?"
  while lo <= hi do
    local mid = (lo + hi) // 2
    if names[mid][1] <= a then best = names[mid][2]; lo = mid + 1 else hi = mid - 1 end
  end
  return best
end
local f, tot, by = 0, 0, {}
T = mem:install_read_tap(0x0000, 0xFFFF, "vbic", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  if mem:read_u8(S.S_INVBI) ~= 0 then
    local c = CYC[d + 1]
    tot = tot + c
    local w = where(a)
    by[w] = (by[w] or 0) + c
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local n = END - FROM
    local o = io.open("vbicost.log", "w")
    o:write(string.format("inside the VBI: %.0f cycles a frame\n", tot / n))
    local t = {}
    for k, v in pairs(by) do t[#t + 1] = {k, v} end
    table.sort(t, function(x, y) return x[2] > y[2] end)
    for i = 1, math.min(25, #t) do o:write(string.format("  %-20s %6.0f\n", t[i][1], t[i][2] / n)) end
    o:close(); M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
