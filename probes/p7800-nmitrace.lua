-- each NMI in frames FROM..FROM+N: its number in the frame (after the
-- increment), the flags as it enters (INVBI, INDLI, VBIPEND, NMIEN), and what it
-- did: VBI (game VBI run), DLI (game DLI handler entered), VBI deferred,
-- dropped. playkey.lua drives the input. To nmitrace.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "3200")
local N = tonumber(os.getenv("N") or "3")
local f, cur = 0, nil
local o = io.open("nmitrace.log", "w")
local function r(a) return mem:read_u8(a) end
local function flush()
  if cur then o:write(cur .. "\n"); cur = nil end
end
T = mem:install_read_tap(0x0000, 0xFFFF, "nt", function(a, d)
  if a ~= PCs.value or f < FROM or f >= FROM + N then return d end
  if a == S.Nmi then
    flush()
    cur = string.format("f%d NMI #%d invbi %d indli %d vbipend %d nmien %02X:", f, r(S.S_NMICOUNT) + 1,
      r(S.S_INVBI), r(S.S_INDLI), r(S.S_VBIPEND), r(S.S_NMIEN))
  elseif cur then
    if a == S.NmiVbiRun then cur = cur .. " VBI"
    elseif a == 0x7026 then cur = cur .. " DLI"
    elseif a == S.NmiDone then cur = cur .. " done"; flush()
    end
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f == FROM + N then flush(); o:close(); M:exit() end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
