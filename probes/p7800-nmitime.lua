-- per frame from FROM to END: each NMI's arrival, each game DLI handler's
-- start (NmiDliRun) and end (DliExit), each deferred DLI (DliAgain), and the
-- vertical blank's start (NmiVbi), in estimated scanlines (emulated time since
-- the frame's end, 1 / (59.92 x 263) s a line); to nmitime.log. No input.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local t0, f = 0, 0
local function line() return math.floor((M.time:as_double() - t0) * 59.92 * 263) end
local NAMES = {[S.Nmi] = "nmi", [S.NmiDliRun] = "dli", [S.DliExit] = "end", [S.DliAgain] = "again",
               [S.NmiVbi] = "vbi", [S.NmiDliNot] = "held"}
local ev = {}
T = mem:install_read_tap(0x0000, 0xFFFF, "nt", function(a, d)
  if f >= FROM and NAMES[a] and a == cpu.state["PC"].value then ev[#ev + 1] = NAMES[a] .. "@" .. line() end
  return d end)
local o = io.open("nmitime.log", "w")
emu.register_frame_done(function()
  t0 = M.time:as_double()
  f = f + 1
  if f >= FROM then o:write(string.format("f%d %s\n", f, table.concat(ev, " "))); ev = {} end
  if f >= END then o:close(); M:exit() end
end)

if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
