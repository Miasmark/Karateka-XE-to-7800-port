-- writes to ADDR (hex) per BLOCK frames (default 200) from FROM to END, with
-- the values written and the writers' PCs (up to four each); either machine;
-- CHEAT: a script to load first. To writecount.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local A = tonumber(os.getenv("ADDR"), 16)
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "60000")
local BLOCK = tonumber(os.getenv("BLOCK") or "200")
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local f, n, vals, pcs = 0, 0, {}, {}
local o = io.open("writecount.log", "w")
W = mem:install_write_tap(A, A, "wc", function(a, d)
  if f >= FROM then n = n + 1; vals[d] = (vals[d] or 0) + 1; local p = cpu.state["PC"].value; pcs[p] = (pcs[p] or 0) + 1 end
  return d end)
local function top(t)
  local l = {}
  for k, v in pairs(t) do l[#l + 1] = {k, v} end
  table.sort(l, function(x, y) return x[2] > y[2] end)
  local s = {}
  for i = 1, math.min(4, #l) do s[#s + 1] = string.format("%02X:%d", l[i][1], l[i][2]) end
  return table.concat(s, " ")
end
emu.register_frame_done(function()
  f = f + 1
  if f > FROM and (f - FROM) % BLOCK == 0 then
    o:write(string.format("f%d D0=%02X writes %d  values %s  pcs %s\n", f, mem:read_u8(0xD0), n, top(vals), top(pcs)))
    o:flush(); n, vals, pcs = 0, {}, {}
  end
  if f >= END then o:close(); M:exit() end
end)
