-- the port: game writes past the end of framebuffer A ($6FF0-$6FFF and the
-- engine above, to $7FFF) other than the system's own copies; per PC the
-- address range, count and frames; plus the first 40 writes in detail; to
-- overrun.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "3010")
local f, st, first = 0, {}, {}
W = mem:install_write_tap(0x6FF0, 0x7FFF, "ov", function(a, d)
  local pc = cpu.state["PC"].value
  if pc >= 0xE000 then return d end              -- the system (loads)
  if pc >= 0x7000 and pc < 0x8000 and a >= 0x7000 then
    -- the engine writing into itself is its own self-modification, unless it is the blitter
    if pc ~= 0x7927 and pc ~= 0x7946 and pc ~= 0x7B12 and pc ~= 0x7B2F then return d end
  end
  local s = st[pc] or {lo = a, hi = a, n = 0, f1 = f}
  s.lo = math.min(s.lo, a); s.hi = math.max(s.hi, a); s.n = s.n + 1; s.f2 = f
  st[pc] = s
  if #first < 40 then first[#first + 1] = string.format("f%d PC=%04X %04X<-%02X dst %02X%02X y? src %02X%02X", f, pc, a, d,
    mem:read_u8(0xD6), mem:read_u8(0xD5), mem:read_u8(0xCA), mem:read_u8(0xC9)) end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("overrun.log", "w")
    for pc, s in pairs(st) do o:write(string.format("PC %04X: $%04X-$%04X, %d writes, frames %d-%d\n", pc, s.lo, s.hi, s.n, s.f1, s.f2)) end
    for _, l in ipairs(first) do o:write(l .. "\n") end
    o:close(); M:exit()
  end
end)
