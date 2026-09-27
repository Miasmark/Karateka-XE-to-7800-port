-- the scanline of every palette write (from emulated time since the last
-- frame boundary, over 262 lines a frame: the offset is MAME's frame boundary,
-- the same in every build, so compare builds with it rather than read lines) (MARIA $20-$3F except WSYNC $24,
-- MSTAT $28, DPPH $2C, DPPL $30, CHBASE $34, CTRL $3C), per frame from FROM
-- to END: "line:reg" in order, one line per frame, collapsed when a frame
-- repeats the last; to palline.log. WITHPLAY=1: playkey drives the input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local t0, dur = nil, nil       -- the last frame boundary, and a frame's length
local function line()
  if not t0 or not dur then return -1 end
  return math.floor((M.time:as_double() - t0) / (dur / 262))
end
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "3100")
-- also "N" at each NMI's entry and "W" at each WSYNC write, by line
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local NMI = SYM_ADDR.Nmi
local PCs = cpu.state["PC"]
local skip = {[0x24] = true, [0x28] = true, [0x2C] = true, [0x30] = true, [0x34] = true, [0x3C] = true}
local f, cur, last, run = 0, {}, nil, 0
local o = io.open("palline.log", "w")
P = mem:install_write_tap(0x0020, 0x003F, "pal", function(a, d)
  if f >= FROM then
    if a == 0x24 then cur[#cur + 1] = string.format("%d:W", line())
    elseif not skip[a] then cur[#cur + 1] = string.format("%d:%02X", line(), a) end
  end
  return d end)
NT = mem:install_read_tap(NMI, NMI, "nmi", function(a, d)
  if f >= FROM and a == PCs.value then cur[#cur + 1] = string.format("%d:N", line()) end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  local t = M.time:as_double()
  if t0 then dur = t - t0 end
  t0 = t
  if f > FROM then
    local line = table.concat(cur, " ")
    if line == last then run = run + 1 else
      if last then o:write(string.format("  x%d\n", run)) end
      o:write(string.format("f%d %s", f, line)); last, run = line, 1
    end
  end
  cur = {}
  if f >= END then o:write(string.format("  x%d\n", run)); o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
