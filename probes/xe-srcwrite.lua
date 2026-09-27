-- the original: writes to $04 (the blit source's high byte) with values
-- $12-$22 (scene code) between FROM and END: PC and value, counted; plus the
-- previous instruction (to see where the value came from); to srcwrite.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM = tonumber(os.getenv("FROM") or "2650")
local END = tonumber(os.getenv("END") or "4650")
local f, cnt, prevpc, lastpc = 0, {}, 0, 0
T = mem:install_read_tap(0x0000, 0xFFFF, "pp", function(a, d)
  if a == PCs.value then prevpc = lastpc; lastpc = a end
  return d end)
W = mem:install_write_tap(0x0004, 0x0004, "w4", function(a, d)
  if f >= FROM and d >= 0x12 and d <= 0x22 then
    local k = string.format("%04X (after %04X) <- %02X", PCs.value, prevpc, d)
    cnt[k] = (cnt[k] or 0) + 1
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f >= END then
    local o = io.open("srcwrite.log", "w")
    for k, v in pairs(cnt) do o:write(string.format("%s  x%d\n", k, v)) end
    o:close(); M:exit()
  end
end)
