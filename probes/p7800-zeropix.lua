-- which rows show MARIA's background (pixel value 0 in 160A) in play: at
-- every flip, per row 0-TOP of the buffer going on screen, whether any byte
-- has a 00 pixel pair; counted per scene ($D0), from FROM to END. To
-- zeropix.log. WITHPLAY=1: playkey drives.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "12000")
local TOP = tonumber(os.getenv("TOP") or "80")
local f, pending, shown, by = 0, nil, nil, {}
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) pending = d; return d end)
local done = false
local function report()
  if done then return end
  done = true
  local o = io.open("zeropix.log", "w")
  for sc, t in pairs(by) do
    o:write(string.format("scene %d: %d pictures; rows with a background pixel (row:pictures)\n ", sc, t.n))
    for r = 0, TOP do if t[r] > 0 then o:write(string.format(" %d:%d", r, t[r])) end end
    o:write("\n")
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
      local base = (shown == 0x22) and 0x5808 or 0x4010
      local t = by[sc]
      if not t then t = {n = 0}; for r = 0, TOP do t[r] = 0 end; by[sc] = t end
      t.n = t.n + 1
      for r = 0, TOP do
        for c = 0, 39 do
          local b = mem:read_u8(base + 40 * r + c)
          if b & 0xC0 == 0 or b & 0x30 == 0 or b & 0x0C == 0 or b & 0x03 == 0 then t[r] = t[r] + 1; break end
        end
      end
    end
  end
  if f >= END then report(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
