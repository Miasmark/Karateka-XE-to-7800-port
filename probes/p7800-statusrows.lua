-- writes into the status rows (bitmap rows 146-153 of either buffer) made
-- outside the status bar's own calls ($9B00/$9B03/$9B06, entered to return):
-- by PC, with counts; from FROM to END, to statusrows.log. WITHPLAY=1.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local f, inside, isp = 0, false, 0
local other, own = {}, 0
T = mem:install_read_tap(0x0000, 0xFFFF, "st", function(a, d)
  if a ~= PCs.value then return d end
  local sp = SPs.value & 0xFF
  if inside and sp > isp then inside = false end
  if not inside and (a == 0x9B00 or a == 0x9B03 or a == 0x9B06) then inside = true; isp = sp end
  return d end)
local function fb(base)
  return function(a, d)
    if f < FROM then return d end
    local r = (a - base) // 40
    if r >= 146 and r <= 152 or (r == 153 and (a - base) < 6120) then
      if inside then own = own + 1 else
        local k = string.format("PC %04X scene %d", PCs.value, mem:read_u8(0x1E01))
        local e = other[k] or {n = 0, f1 = f, rows = {}}
        e.n = e.n + 1; e.f2 = f; e.rows[r] = true
        e.frames = e.frames or {}; e.frames[f] = (e.frames[f] or 0) + 1
        other[k] = e end
    end
    return d end
end
W1 = mem:install_write_tap(0x4010 + 146 * 40, 0x57F7, "fbB", fb(0x4010))
W2 = mem:install_write_tap(0x5808 + 146 * 40, 0x6FEF, "fbA", fb(0x5808))
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("statusrows.log", "w")
  o:write(string.format("frames %d-%d: %d writes by the status bar's calls; others:\n", FROM, f, own))
  for k, e in pairs(other) do
    local rs = {}
    for r in pairs(e.rows) do rs[#rs + 1] = r end
    table.sort(rs)
    o:write(string.format("  %s: %d writes, frames %d-%d, rows %d-%d\n", k, e.n, e.f1, e.f2, rs[1], rs[#rs]))
    if not k:match("scene 0") then
      local fs = {}
      for fr in pairs(e.frames) do fs[#fs + 1] = fr end
      table.sort(fs)
      local t = {}
      for i = 1, math.min(40, #fs) do t[#t + 1] = string.format("%d:%d", fs[i], e.frames[fs[i]]) end
      o:write("    frames: " .. table.concat(t, " ") .. "\n")
    end
  end
  o:close()
end
STOPS = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function() f = f + 1; if f >= END then report(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
