-- what reaches into the top of the picture in play: at every buffer flip,
-- the buffer going on screen's rows 0-TOP (default 60) are compared with
-- row 0's first byte; the box (rows, byte columns) of bytes that differ is
-- counted per scene ($D0), with the frames it was seen, and the first
-- showing of each new box (up to 40) is snapshotted (screen shows it the
-- frame after), with the top differing row of each byte column. Per scene, also the first row that is ever not uniform.
-- To topband.log.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "42000")
local TOP = tonumber(os.getenv("TOP") or "60")
local f, pending, shown, snaps, snapnext = 0, nil, nil, 0, false
local boxes, scenes = {}, {}
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) pending = d; return d end)
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("topband.log", "w")
  for sc, t in pairs(scenes) do
    o:write(string.format("scene %d: %d pictures, sky value %02X, first row ever mixed %s\n", sc, t.n, t.v, t.first or "none"))
  end
  local l = {}
  for k, e in pairs(boxes) do l[#l + 1] = {k, e} end
  table.sort(l, function(x, y) return x[2].f1 < y[2].f1 end)
  for _, x in ipairs(l) do
    o:write(string.format("%s: %d pictures, frames %d-%d%s\n", x[1], x[2].n, x[2].f1, x[2].f2, x[2].snap and (" snap " .. x[2].snap) or ""))
    o:write("    top row by column: " .. x[2].tops .. "\n")
  end
  o:close()
end
STOP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function()
  f = f + 1
  if snapnext then snapnext = false; M.video:snapshot() end
  if pending and pending ~= shown then
    shown = pending
    local sc = mem:read_u8(0xD0)
    if f >= FROM and sc ~= 0 and (shown == 0x22 or shown == 0x24) then
      local base = (shown == 0x22) and 0x5808 or 0x4010
      local v = mem:read_u8(base)
      local r0, r1, c0, c1 = nil, nil, 99, -1
      for r = 0, TOP do
        for c = 0, 39 do
          if mem:read_u8(base + 40 * r + c) ~= v then
            r0 = r0 or r; r1 = r
            if c < c0 then c0 = c end
            if c > c1 then c1 = c end
          end
        end
      end
      local t = scenes[sc] or {n = 0, v = v}
      scenes[sc] = t
      t.n = t.n + 1
      if r0 and (not t.first or r0 < t.first) then t.first = r0 end
      if r0 then
        local k = string.format("scene %d rows %d-%d cols %d-%d", sc, r0, r1, c0, c1)
        local e = boxes[k]
        if not e then
          local tops = {}
          for c = 0, 39 do
            local top = "--"
            for r = 0, TOP do
              if mem:read_u8(base + 40 * r + c) ~= v then top = string.format("%02d", r); break end
            end
            tops[#tops + 1] = top
          end
          e = {n = 0, f1 = f, tops = table.concat(tops, " ")}
          boxes[k] = e
          if snaps < 40 then snaps = snaps + 1; e.snap = snaps - 1; snapnext = true end
        end
        e.n = e.n + 1; e.f2 = f
      end
    end
  end
  if f >= END then report(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
