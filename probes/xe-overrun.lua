-- the original: writes past the end of framebuffer A ($5FF0-$6FFF) by game code
-- other than the loaders: lowest/highest address and count per PC; to overrun.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "4000")
local f, st = 0, {}
W = mem:install_write_tap(0x5FF0, 0x6FFF, "ov", function(a, d)
  local pc = cpu.state["PC"].value
  if pc >= 0xB2CC and pc <= 0xB2EB then return d end   -- the loader's copy
  if pc >= 0xC000 then return d end                      -- the OS
  local s = st[pc] or {lo = a, hi = a, n = 0, f1 = f}
  s.lo = math.min(s.lo, a); s.hi = math.max(s.hi, a); s.n = s.n + 1; s.f2 = f
  st[pc] = s
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("overrun.log", "w")
    for pc, s in pairs(st) do o:write(string.format("PC %04X: $%04X-$%04X, %d writes, frames %d-%d\n", pc, s.lo, s.hi, s.n, s.f1, s.f2)) end
    o:close(); M:exit()
  end
end)
