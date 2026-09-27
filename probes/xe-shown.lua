-- the original: writes into the framebuffer on screen, per BLOCK frames. ANTIC
-- takes DLISTL/H at once; the buffer a list shows is its first LMS address
-- (A $4808-$5FEF, B $3010-$47F7). playkey.lua drives the input (MACHINE=xe).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local BLOCK = tonumber(os.getenv("BLOCK") or "100")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local dl, shown = 0, "A"
local f, into, other, frames_hit, hit_this = 0, 0, 0, 0, false
local o = io.open("shown.log", "w")
local function which(addr)
  for k = 0, 40 do
    local b = mem:read_u8(addr + k)
    if (b & 0x0F) >= 2 and (b & 0x40) ~= 0 then
      local hi = mem:read_u8(addr + k + 2)
      return (hi >= 0x48) and "A" or "B"
    end
  end
  return shown
end
D1 = mem:install_write_tap(0xD402, 0xD403, "dlist", function(a, d)
  if a == 0xD402 then dl = (dl & 0xFF00) | d else dl = (dl & 0xFF) | (d << 8); shown = which(dl) end
  return d end)
local function fb(a, d)
  if f < FROM then return d end
  local buf = (a >= 0x4808) and "A" or "B"
  if buf == shown then into = into + 1; hit_this = true else other = other + 1 end
  return d end
W1 = mem:install_write_tap(0x3010, 0x47F7, "fbB", fb)
W2 = mem:install_write_tap(0x4808, 0x5FEF, "fbA", fb)
emu.register_frame_done(function()
  f = f + 1
  if hit_this then frames_hit = frames_hit + 1 end
  hit_this = false
  if f > FROM and (f - FROM) % BLOCK == 0 then
    o:write(string.format("f%d flip %d: writes into the shown buffer %d, into the hidden one %d; frames with any %d of %d\n",
      f, PLAYKEY_N or 0, into, other, frames_hit, BLOCK))
    o:flush()
    into, other, frames_hit = 0, 0, 0
  end
  if f >= END then o:close(); M:exit() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
