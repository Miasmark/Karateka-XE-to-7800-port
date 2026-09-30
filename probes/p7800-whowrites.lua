-- who writes LO-HI (hex) from frame FROM on: the PC and frame of the first
-- MAXN writes; to whowrites.log. RIGHT=a-b holds the stick right.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local LO, HI = tonumber(os.getenv("LO") or "4040", 16), tonumber(os.getenv("HI") or "409F", 16)
local FROM, END, MAXN = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "400"), tonumber(os.getenv("MAXN") or "40")
local f, n = 0, 0
local o = io.open("whowrites.log", "w")
W = mem:install_write_tap(LO, HI, "ww", function(a, d)
  if f >= FROM and n < MAXN then
    n = n + 1
    o:write(string.format("f%d $%04X <- %02X from PC %04X\n", f, a, d, cpu.state["PC"].value))
  end
  return d end)
local function field(name)
  for _, p in pairs(M.ioport.ports) do for n, fl in pairs(p.fields) do if n == name then return fl end end end
end
local right = field("P1 Right")
local r0, r1 = (os.getenv("RIGHT") or ""):match("(%d+)-(%d+)")
r0, r1 = tonumber(r0), tonumber(r1)
emu.register_frame_done(function()
  f = f + 1
  if right then right:set_value((r0 and f >= r0 and f <= r1) and 1 or 0) end
  if f >= END then o:close(); M:exit() end
end)
