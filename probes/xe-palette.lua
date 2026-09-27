-- the original's colour writes per frame (GTIA COLPF0-3 $D016-$D019, COLBK
-- $D01A) keyed by the DLI counter $0F14 at the time; pattern counts as
-- p7800-palette.lua. playkey.lua drives the input (MACHINE=xe).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local FROM = tonumber(os.getenv("FROM") or "2000")
local END = tonumber(os.getenv("END") or "4000")
local f, cur, frames = 0, {}, {}
PW = mem:install_write_tap(0xD016, 0xD01A, "pal", function(a, d)
  if f >= FROM then cur[#cur + 1] = string.format("%d:%04X=%02X", mem:read_u8(0x0F14), a, d) end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > FROM then frames[#frames + 1] = {f, table.concat(cur, " "), PLAYKEY_N or 0} end
  cur = {}
  if f >= END then
    local count = {}
    for _, fr in ipairs(frames) do count[fr[2]] = (count[fr[2]] or 0) + 1 end
    local o = io.open("palette.log", "w")
    local pats = {}
    for p, c in pairs(count) do pats[#pats + 1] = {p, c} end
    table.sort(pats, function(x, y) return x[2] > y[2] end)
    o:write(string.format("%d frames, %d distinct patterns\n", #frames, #pats))
    for i, pc in ipairs(pats) do
      o:write(string.format("pattern %d x%d: %s\n", i, pc[2], pc[1]))
      if i >= 12 then break end
    end
    o:close(); M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
