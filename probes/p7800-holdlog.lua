-- the game's picture hold ($0AFC/$0AFD, on the 7800 $1A86/$1A87: whole
-- frames $B60F waits after the flip's vertical blank) as each flip starts
-- (DPPH change), with the frames since the last flip; a histogram to
-- holdlog.log from flip FROMFLIP to TOFLIP. WITHPLAY=1: playkey.lua.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local F0, F1 = tonumber(os.getenv("FROMFLIP") or "300"), tonumber(os.getenv("TOFLIP") or "800")
local f, flips, last, lastf = 0, 0, nil, 0
local hold, gap = {}, {}
local maxhold = 0
W = mem:install_write_tap(0x1A86, 0x1A86, "hl", function(a, d)
  if flips >= F0 and d > maxhold then maxhold = d end
  return d end)
D = mem:install_write_tap(0x002C, 0x002C, "hf", function(a, d)
  if last and d ~= last then
    flips = flips + 1
    if flips > F0 and flips <= F1 then
      local g = f - lastf
      gap[g] = (gap[g] or 0) + 1
    end
    lastf = f
    if flips >= F1 then
      local o = io.open("holdlog.log", "w")
      o:write(string.format("pictures %d-%d: frames between flips:", F0, F1))
      local ks = {}
      for k in pairs(gap) do ks[#ks + 1] = k end
      table.sort(ks)
      for _, k in ipairs(ks) do o:write(string.format(" %d:%d", k, gap[k])) end
      o:write(string.format("\nlargest hold written to $1A86: %d\n", maxhold))
      o:close(); M:exit()
    end
  end
  last = d; return d end)
emu.register_frame_done(function() f = f + 1 end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
