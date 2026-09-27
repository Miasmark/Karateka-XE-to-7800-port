-- the original's RAM $0000-$0FFF when scene WANT (default 4) begins: at the
-- first write of WANT to $D0, and again DELAY frames later (default 60); to
-- scenedump.bin (both, 8K). CHEAT: a script to load first (the one a
-- recording was made with). With SCENE set, playkey.lua's substitution
-- makes the start (the swapped start, for comparison).
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local WANT = tonumber(os.getenv("WANT") or "4")
local DELAY = tonumber(os.getenv("DELAY") or "60")
if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local f, at, dumps = 0, nil, {}
local function dump()
  local t = {}
  for a = 0, 0x0FFF do t[#t + 1] = string.char(mem:read_u8(a)) end
  return table.concat(t)
end
DW = mem:install_write_tap(0x00D0, 0x00D0, "d0", function(a, d)
  if not at and d == WANT then at = f + 1 end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if at and (f == at or f == at + DELAY) then dumps[#dumps + 1] = dump() end
  if #dumps == 2 then
    local o = io.open("scenedump.bin", "wb"); o:write(dumps[1] .. dumps[2]); o:close()
    local l = io.open("scenedump.txt", "w"); l:write(string.format("scene %d began at frame %d\n", WANT, at)); l:close()
    M:exit()
  end
end)
if os.getenv("SCENE") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
