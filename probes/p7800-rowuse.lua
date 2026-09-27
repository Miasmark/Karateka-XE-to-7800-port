-- which bitmap rows carry anything during play: at every buffer flip (DPPH
-- change), each of the 153 rows of the buffer going on screen is classed as
-- uniform (all 40 bytes one value) or mixed; per row, the values seen and
-- how often it was mixed, from frame FROM to END, per scene in play ($D0;
-- scene 0 left out); to rowuse.log. Also which
-- rows MARIA is given at all (the DLL's zones). WITHPLAY=1: playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "9000")
local f, flips = 0, 0
local byscene = {}          -- scene ($D0) -> rows; scene 0 (title, story) left out
local function rows_of(sc)
  if not byscene[sc] then
    local t = {flips = 0}
    for r = 0, 152 do t[r] = {mixed = 0, vals = {}} end
    byscene[sc] = t
  end
  return byscene[sc]
end
local pending = nil
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) pending = d; return d end)
local shown = nil
local reported = false
local function report()
  if reported then return end
  reported = true
  local o = io.open("rowuse.log", "w")
  for sc, rows in pairs(byscene) do
    o:write(string.format("scene %d: flips %d (frames %d-%d)\n", sc, rows.flips, FROM, f))
    for r = 0, 152 do
      local t = {}
      for v, n in pairs(rows[r].vals) do t[#t + 1] = string.format("%02Xx%d", v, n) end
      table.sort(t)
      o:write(string.format("row %3d: mixed %d; uniform %s\n", r, rows[r].mixed, table.concat(t, " ")))
    end
  end
  o:close()
end
STOP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function()
  f = f + 1
  if pending and pending ~= shown then
    shown = pending
    local sc = mem:read_u8(0xD0)
    if f >= FROM and sc ~= 0 and (shown == 0x22 or shown == 0x24) then
      flips = flips + 1
      local rows = rows_of(sc)
      rows.flips = rows.flips + 1
      local base = (shown == 0x22) and 0x5808 or 0x4010
      for r = 0, 152 do
        local a = base + 40 * r
        local v0, uni = mem:read_u8(a), true
        for c = 1, 39 do if mem:read_u8(a + c) ~= v0 then uni = false; break end end
        if uni then rows[r].vals[v0] = (rows[r].vals[v0] or 0) + 1 else rows[r].mixed = rows[r].mixed + 1 end
      end
    end
  end
  if f >= END then report(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
