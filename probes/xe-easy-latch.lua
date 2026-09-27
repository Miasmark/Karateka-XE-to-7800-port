-- xe-easy-latch.lua -- Karateka XEGS (MAME `xegs`): easy mode (xe-easy.lua)
-- plus a trial of the control change the port may make.
--
-- The game reads the stick (PORTA, at $AD09) only when the player's fighter
-- reaches a decision point: every 6-10 frames depending on the scene
-- (measured over inp/xe-01-easy.inp). A push that ends between two reads is
-- never seen, which is why a kick needs a long press: pushes of 1-3 frames
-- were missed 55 times out of 67, 4-7 frames about half the time.
--
-- The trial: the stick is sampled every frame and the latest push is kept.
-- When the game reads the stick and it is back in the centre, the kept push
-- is handed over once, then forgotten. A push still held at the read is
-- read live, as before. So a tap arrives once, at the next decision point,
-- and a hold still reads as a hold: nothing becomes a longer input than
-- the player made. (A latch on the fire button was tried on the 7800
-- version and withdrawn because it turned taps into holds; this one is on
-- the stick, which the game reads only at decision points, and it clears
-- after every read.)

dofile((debug.getinfo(1, "S").source:sub(2):gsub("[^/\\]*$", "")) .. "xe-easy.lua")

local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PC = cpu.state["PC"]
local joy = M.ioport.ports[":ctrl1:joy:JOY"]

XE_LATCH = { kept = nil }
XE_LATCH.tap = mem:install_read_tap(0xD300, 0xD300, "latch-stick", function(a, d)
  if PC.value ~= 0xAD09 then return d end
  local out = d
  if (d & 0x0F) == 0x0F and XE_LATCH.kept then
    out = (d & 0xF0) | XE_LATCH.kept
  end
  XE_LATCH.kept = nil
  return out
end)

emu.register_frame_done(function()
  -- PORTA's low nibble is stick 1, active low; the port reads the same bits
  local v = joy:read() & 0x0F
  if v ~= 0x0F then XE_LATCH.kept = v end
end)
