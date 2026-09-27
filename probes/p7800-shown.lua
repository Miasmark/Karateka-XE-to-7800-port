-- writes into the framebuffer that is on screen, while it is on screen, per
-- BLOCK frames (default 100): the displayed list follows DPPH as written (MARIA takes it at the next
-- frame start, taken here as the frame boundary); DLL_A ($22xx) shows
-- buffer A ($5808-$6FEF), DLL_B ($24xx) buffer B ($4010-$57F7). The game
-- should only ever draw into the hidden one. playkey.lua drives the input.
-- To shown.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local BLOCK = tonumber(os.getenv("BLOCK") or "100")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local pending, shown = 0x22, 0x22
local f, into, other, frames_hit = 0, 0, 0, 0
local hit_this = false
local o = io.open("shown.log", "w")
-- DETAIL=1: each write into the shown buffer, to detail.log
DETAIL = os.getenv("DETAIL") and io.open("detail.log", "w") or nil
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) pending = d; return d end)
local function fb(a, d)
  if f < FROM then return d end
  local buf = (a >= 0x5808) and 0x22 or 0x24
  -- after this frame's switch (DPPH written: the game's VBI has run, below the
  -- picture) the old buffer is no longer on view; only earlier writes show
  if buf == shown and pending == shown then
    into = into + 1; hit_this = true
    if DETAIL then DETAIL:write(string.format("f%d PC=%04X %04X<-%02X shown %02X pending %02X busy %d invbi %d\n", f,
      cpu.state["PC"].value, a, d, shown, pending, mem:read_u8(0x1E43), mem:read_u8(0x1E4B))) end
  else other = other + 1 end
  return d end
W1 = mem:install_write_tap(0x4010, 0x57F7, "fbB", fb)
W2 = mem:install_write_tap(0x5808, 0x6FEF, "fbA", fb)
emu.register_frame_done(function()
  f = f + 1
  if hit_this then frames_hit = frames_hit + 1 end
  hit_this = false
  shown = pending
  if f > FROM and (f - FROM) % BLOCK == 0 then
    o:write(string.format("f%d flip %d: writes into the shown buffer %d, into the hidden one %d; frames with any %d of %d\n",
      f, PLAYKEY_N or 0, into, other, frames_hit, BLOCK))
    o:flush()
    into, other, frames_hit = 0, 0, 0
  end
  if f >= END then o:close(); M:exit() end
end)
if not os.getenv("NOPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end   -- NOPLAY=1: no input (the attract sequence)
