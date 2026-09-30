-- who writes the framebuffer pages ($4000-$72FF) and engine1's ROM copy
-- ($F200-$F402, where a write is lost), by PC: count, first frame and
-- address; and every write to a page's spare bytes (offsets 0-15: only the
-- game's record at $40FF/$4100 and the gaps should land there). To
-- fbwatch.log, written every 1,000 frames and at the end. END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local END = tonumber(os.getenv("END") or "20000")
local f = 0
local fb, rom, spare = {}, {}, {}
local function note(t, a, d)
  local pc = PCs.value
  local e = t[pc]
  if not e then e = {n = 0, f = f, a = a, lo = a, hi = a}; t[pc] = e end
  e.n = e.n + 1
  if a < e.lo then e.lo = a end
  if a > e.hi then e.hi = a end
end
W1 = mem:install_write_tap(0x4010, 0x72FF, "fw", function(a, d)
  note(fb, a, d)
  if (a & 0xFF) < 16 then note(spare, a, d) end
  return d end)
W2 = mem:install_write_tap(0xF200, 0xF402, "rw", function(a, d) note(rom, a, d); return d end)
local function dump()
  local o = io.open("fbwatch.log", "w")
  for _, part in ipairs({{"framebuffer pages", fb}, {"spare bytes (page offsets 0-15)", spare}, {"engine1 ROM", rom}}) do
    o:write(part[1] .. ":\n")
    local l = {}
    for pc, e in pairs(part[2]) do l[#l + 1] = {pc, e} end
    table.sort(l, function(x, y) return x[2].n > y[2].n end)
    for _, x in ipairs(l) do
      o:write(string.format("  PC $%04X: %d writes, first f%d at $%04X, range $%04X-$%04X\n", x[1], x[2].n, x[2].f, x[2].a, x[2].lo, x[2].hi))
    end
  end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then dump() end
  if f >= END then dump(); M:exit() end
end)
