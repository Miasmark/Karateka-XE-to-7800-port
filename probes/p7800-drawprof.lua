-- where the game's drawing time goes: each call of the blitters (XEGS $284E,
-- $2B82, $2B8B), the fills ($2CCD rectangle, $2D03 pattern) and the clear
-- ($280F) is timed in emulated time from entry to return (so MARIA's DMA
-- counts, as it does for the game), minus the NMIs inside it, and charged to
-- a key: the blits by source address ($03/$04) and size, the fills by their
-- rectangle; from frame FROM to END, with the flips (DPPH changes) counted.
-- To drawprof.log, in cycles per flip (1.79 MHz). WITHPLAY=1: playkey drives.
-- PCS=1: executed cycles by PC (ONLY: just the calls whose key has this).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "6000")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local ENTRY = {[0x784E] = "blitA", [0x7B82] = "blitB", [0x7B8B] = "blitC",
               [0x7CCD] = "fill", [0x7D03] = "pattern", [0x780F] = "clear"}
local f, flips, lastd = 0, 0, nil
local cur = nil                 -- {key, sp, t0, nmi}
local nmi_t0, in_nmi = nil, false
local final = nil
local by, calls = {}, {}
local HZ = 1789772.5
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
local exe, pcs = {}, {}
local ONLY = os.getenv("ONLY")       -- PCS: only calls whose key contains this
T = mem:install_read_tap(0x0000, 0xFFFF, "prof", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  if not final then final = S.NmiQuit; while mem:read_u8(final) ~= 0x40 do final = final + 1 end end
  local t = M.time:as_double()
  if a == S.Nmi then nmi_t0 = t; return d end
  if a == final and nmi_t0 then
    if cur then cur.nmi = cur.nmi + (t - nmi_t0) end
    nmi_t0 = nil
    return d
  end
  if nmi_t0 then return d end
  if cur then
    cur.exe = cur.exe + CYC[d + 1]
    if os.getenv("PCS") and (not ONLY or cur.key:find(ONLY, 1, true)) then pcs[a] = (pcs[a] or 0) + CYC[d + 1] end
  end
  local sp = SPs.value & 0xFF
  if cur and sp > cur.sp then            -- returned
    local dt = (t - cur.t0 - cur.nmi) * HZ
    by[cur.key] = (by[cur.key] or 0) + dt
    exe[cur.key] = (exe[cur.key] or 0) + cur.exe
    calls[cur.key] = (calls[cur.key] or 0) + 1
    cur = nil
  end
  local kind = ENTRY[a]
  if kind and not cur then
    local key
    if kind:sub(1, 4) == "blit" then
      local src = z(0x04) * 256 + z(0x03)
      key = os.getenv("BYCOL") and string.format("%s src $%04X col %d", kind, src, z(0x05)) or string.format("%s src $%04X %dx%d", kind, src, mem:read_u8(src), mem:read_u8(src + 1))
    elseif kind == "clear" then
      key = "clear"
    else
      key = os.getenv("BYCOL") and string.format("%s cols %d-%d rows %d-%d", kind, z(0x05), z(0x09), z(0x06), z(0x08)) or kind
    end
    cur = {key = key, sp = sp, t0 = t, nmi = 0, exe = 0}
  end
  return d end)
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if f >= FROM and lastd and d ~= lastd then flips = flips + 1 end
  lastd = d; return d end)
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("drawprof.log", "w")
  local frames = math.max(f - FROM, 1)
  local total = 0
  for _, v in pairs(by) do total = total + v end
  o:write(string.format("frames %d-%d, flips %d: drawing %.0f cycles a flip, %.0f a frame (of 29,868)\n",
    FROM, f, flips, total / math.max(flips, 1), total / frames))
  local t = {}
  for k, v in pairs(by) do t[#t + 1] = {k, v} end
  table.sort(t, function(x, y) return x[2] > y[2] end)
  for i = 1, math.min(30, #t) do
    o:write(string.format("  %6.0f a flip  %5.1f%%  %4d calls  %5.0f a call (%5.0f executed)  %s\n",
      t[i][2] / math.max(flips, 1), 100 * t[i][2] / total, calls[t[i][1]],
      t[i][2] / calls[t[i][1]], (exe[t[i][1]] or 0) / calls[t[i][1]], t[i][1]))
  end
  if os.getenv("PCS") then
    local l = {}
    for a, n in pairs(pcs) do l[#l + 1] = {a, n} end
    table.sort(l, function(x, y) return x[2] > y[2] end)
    for i = 1, math.min(tonumber(os.getenv("NPCS") or "25"), #l) do o:write(string.format("    PC %04X %s: %d\n", l[i][1], SYM_NAME[l[i][1]] or "", l[i][2])) end
  end
  o:close()
end
STOPD = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then report(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
