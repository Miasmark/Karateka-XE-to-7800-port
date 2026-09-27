-- per frame from FROM to END: the list MARIA shows (DPPH/DPPL as last
-- written before the frame starts), whether it is the blank list, and calls
-- of FrameGo and FrameBlank in that frame (FrameBlank with DMACTL and the list asked for);
-- runs of identical frames are collapsed; to blanklog.log. WITHPLAY=1 drives
-- input with playkey.lua.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local f, dpph, dppl = 0, 0, 0
local calls = {}
local o = io.open("blanklog.log", "w")
D1 = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d) dpph = d; return d end)
D2 = mem:install_write_tap(0x0030, 0x0030, "dppl", function(a, d) dppl = d; return d end)
local function caller()
  local sp = cpu.state["SP"].value & 0xFF
  local lo, hi = mem:read_u8(0x100 + ((sp + 1) & 0xFF)), mem:read_u8(0x100 + ((sp + 2) & 0xFF))
  return string.format("%04X", ((hi << 8) | lo) + 1)
end
T = mem:install_read_tap(0xE000, 0xFFFF, "calls", function(a, d)
  if f < FROM or a ~= cpu.state["PC"].value then return d end
  if a == S.FrameBlank then calls[#calls + 1] = string.format("Blank(bank %d invbi %d ndl %02X dmactl %02X dlist %02X%02X)", mem:read_u8(S.S_BANK), mem:read_u8(S.S_INVBI), mem:read_u8(S.SP_NDL),
      mem:read_u8(S.S_DMACTL), mem:read_u8(S.S_DLIST + 1), mem:read_u8(S.S_DLIST))
  elseif a == S.FrameGo then calls[#calls + 1] = "Go" end
  return d end)
local shown, last, run = 0, nil, 0
emu.register_frame_done(function()
  f = f + 1
  if f >= FROM then
    local dll = (dpph << 8) | dppl
    local line = string.format("dll %04X%s %s", shown, shown == S.BLANK_DLL and " BLANK" or "", table.concat(calls, " "))
    if line == last then run = run + 1 else
      if last then o:write(string.format("  x%d\n", run)) end
      o:write(string.format("f%d %s", f, line)); last, run = line, 1
    end
    shown = dll
  end
  calls = {}
  if f >= END then o:write(string.format("  x%d\n", run)); o:close(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
