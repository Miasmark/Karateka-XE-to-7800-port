-- executed CPU cycles from frame FROM to END: in all, a frame, a picture
-- (buffer flips, DPPH changes), and by PC range (RANGES: name=lo-hi,...,
-- hex); to cycles.log. WITHPLAY=1 drives input with playkey.lua (its env
-- applies). Cycles by the 6502's table (page-crossing and branch extras not
-- counted), so a measure for comparing, not an exact count.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "3000")
-- FROMFLIP/TOFLIP: count from the picture FROMFLIP to TOFLIP instead (END still stops)
local F0, F1 = tonumber(os.getenv("FROMFLIP") or "-1"), tonumber(os.getenv("TOFLIP") or "-1")
local allflips, on, fstart, fstop = 0, F0 < 0, nil, nil
local ranges = {}
for name, lo, hi in (os.getenv("RANGES") or ""):gmatch("(%w+)=(%x+)-(%x+)") do ranges[#ranges + 1] = {name, tonumber(lo, 16), tonumber(hi, 16), 0} end
local f, flips, last, total = 0, 0, nil, 0
T = mem:install_read_tap(0x0000, 0xFFFF, "cy", function(a, d)
  if a ~= PCs.value or not on or f < FROM or f >= END then return d end
  local c = CYC[d + 1]
  total = total + c
  for _, r in ipairs(ranges) do if a >= r[2] and a <= r[3] then r[4] = r[4] + c end end
  return d end)
D = mem:install_write_tap(0x002C, 0x002C, "cf", function(a, d)
  if last and d ~= last then
    allflips = allflips + 1
    if F0 >= 0 then
      if allflips == F0 then on = true; fstart = f end
      if allflips == F1 then on = false; fstop = f; M:exit() end
    end
    if on and f >= FROM and f < END then flips = flips + 1 end
  end
  last = d; return d end)
local function report()
  local o = io.open("cycles.log", "w")
  local frames = math.max(math.min(f, END) - FROM, 1)
  if fstart then frames = math.max((fstop or f) - fstart, 1) end
  if fstart then o:write(string.format("pictures %d-%d, frames %d-%d\n", F0, F1, fstart, fstop or f)) end
  o:write(string.format("frames %d-%d: %d pictures (%.1f a 1,000 frames); %d cycles a frame, %d a picture\n",
    FROM, FROM + frames, flips, 1000 * flips / frames, total // frames, total // math.max(flips, 1)))
  for _, r in ipairs(ranges) do
    o:write(string.format("  %-10s %7d a frame %8d a picture\n", r[1], r[4] // frames, r[4] // math.max(flips, 1)))
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then report(); M:exit() end
end)
STOP = emu.add_machine_stop_notifier(function() if f < END then report() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
