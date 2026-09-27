-- a7800_corr.lua -- snapshot + dump MARIA at the same frame
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local FROM = tonumber(os.getenv("A7800_SNAP_FROM") or "20")
local TO   = tonumber(os.getenv("A7800_SNAP_TO") or "120")
local STEP = tonumber(os.getenv("A7800_SNAP_STEP") or "5")
local F = 0
local rd = function(a) return mem:read_u8(a) end

emu.register_frame_done(function()
  F = F + 1
  if F >= FROM and F <= TO and ((F - FROM) % STEP) == 0 then
    pcall(function()
      M.video:snapshot()
      print(string.format("F%03d MARIA ctrl=%02X dpp=%02X%02X inpt=%02X bg=%02X  ram10=%02X%02X%02X%02X",
        F, rd(0), rd(0x04), rd(0x05), rd(3), rd(7), rd(0x1000), rd(0x1001), rd(0x1800), rd(0x1801)))
    end)
  end
  if F >= TO then M:exit() end
end)