-- when MSTAT bit 7 (vertical blank) is set, in CPU cycles since the NMI of each
-- count (S_NMICOUNT) and overall: samples at every instruction fetch, over
-- frames FROM..END; to mstat.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "600")
local END = tonumber(os.getenv("END") or "660")
local f, samples, set, trans = 0, 0, 0, {}
local last = nil
local since = 0
T = mem:install_read_tap(0x0000, 0xFFFF, "ms", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  since = since + 1
  if a == S.Nmi then since = 0 end
  local v = mem:read_u8(0x0028) & 0x80
  samples = samples + 1
  if v ~= 0 then set = set + 1 end
  if last ~= nil and v ~= last then
    trans[#trans + 1] = string.format("f%d %s at %d fetches after an NMI (count %d)", f, v ~= 0 and "on " or "off",
      since, mem:read_u8(S.S_NMICOUNT))
  end
  last = v
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("mstat.log", "w")
    o:write(string.format("MSTAT bit 7 set in %d of %d samples\n", set, samples))
    for i = 1, math.min(20, #trans) do o:write(trans[i] .. "\n") end
    o:close(); M:exit()
  end
end)
