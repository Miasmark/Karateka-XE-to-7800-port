-- a7800_smoke.lua -- boot the ported ROM, snapshot frames, print MARIA state, exit.
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM = tonumber(os.getenv("A7800_SNAP_FROM") or "1")
local TO   = tonumber(os.getenv("A7800_SNAP_TO") or "180")
local STEP = tonumber(os.getenv("A7800_SNAP_STEP") or "6")
local F = 0
emu.register_frame_done(function()
  F = F + 1
  if F >= FROM and F <= TO and ((F - FROM) % STEP) == 0 then
    pcall(function() M.video:snapshot() end)
    local pc = "?"
    pcall(function()
      local d = M.devices[":maincpu"]:debug()
      if d then pc = string.format("%04X", d:pc()) end
    end)
    print(string.format("snap %d  PC=%s", F, pc))
  end
  if F > TO then M:exit() end
end)