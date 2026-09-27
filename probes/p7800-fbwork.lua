-- how the game fills its framebuffers: from frame FROM to END, every write
-- into buffer A or B, by the routine that made it (grouped by PC), with the
-- number of buffer flips (DPPH changes) in the span, and per flip the bytes
-- written and the distinct bytes touched; to fbwork.log. WITHPLAY=1 drives
-- input with playkey.lua (its env applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3600")
local f, flips, last = 0, 0, nil
local bypc, total, touched = {}, 0, {}
local ntouched = 0
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if f >= FROM and last and d ~= last then flips = flips + 1 end
  last = d; return d end)
local function fb(a, d)
  if f < FROM then return d end
  local pc = cpu.state["PC"].value
  bypc[pc] = (bypc[pc] or 0) + 1
  total = total + 1
  if not touched[a] then touched[a] = true; ntouched = ntouched + 1 end
  return d end
W1 = mem:install_write_tap(0x4010, 0x57F7, "fbB", fb)
W2 = mem:install_write_tap(0x5808, 0x6FEF, "fbA", fb)
local function report()
  local o = io.open("fbwork.log", "w")
  local frames = f - FROM
  o:write(string.format("frames %d, flips %d; writes %d (%.0f per flip); distinct bytes %d of 12240\n",
    frames, flips, total, total / math.max(flips, 1), ntouched))
  local t = {}
  for pc, n in pairs(bypc) do t[#t + 1] = {pc, n} end
  table.sort(t, function(x, y) return x[2] > y[2] end)
  for i = 1, math.min(12, #t) do
    o:write(string.format("  PC %04X: %d writes, %.0f per flip\n", t[i][1], t[i][2], t[i][2] / math.max(flips, 1)))
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then report(); M:exit() end
end)
STOP = emu.add_machine_stop_notifier(function() if f < END then report() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
