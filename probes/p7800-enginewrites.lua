-- which bytes of the engine's RAM ($7000-$7FFF) are written after it is
-- loaded (self-modifying code, data kept there): from frame FROM to END,
-- every written address with its first writer PC and count; then the
-- written addresses merged into ranges; to enginewrites.log. WITHPLAY=1
-- drives input with playkey.lua (its env applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "300")
local END = tonumber(os.getenv("END") or "9000")
local f = 0
local seen = {}
W = mem:install_write_tap(0x7000, 0x7FFF, "ew", function(a, d)
  if f < FROM then return d end
  local s = seen[a]
  if not s then s = {pc = cpu.state["PC"].value, n = 0}; seen[a] = s end
  s.n = s.n + 1
  return d end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
emu.register_frame_done(function()
  f = f + 1
  if f >= END or f % 1000 == 0 then
    local o = io.open("enginewrites.log", "w")
    local addrs = {}
    for a in pairs(seen) do addrs[#addrs + 1] = a end
    table.sort(addrs)
    local lo, prev = nil, nil
    local ranges = {}
    for _, a in ipairs(addrs) do
      if lo and a == prev + 1 then prev = a
      else
        if lo then ranges[#ranges + 1] = {lo, prev} end
        lo, prev = a, a
      end
    end
    if lo then ranges[#ranges + 1] = {lo, prev} end
    o:write(string.format("%d engine bytes written from frame %d to %d, in %d ranges:\n", #addrs, FROM, END, #ranges))
    for _, r in ipairs(ranges) do
      local s = seen[r[1]]
      o:write(string.format("  $%04X-$%04X (%d bytes), first by PC $%04X\n", r[1], r[2], r[2] - r[1] + 1, s.pc))
    end
    o:close()
    if f >= END then M:exit() end
  end
end)
