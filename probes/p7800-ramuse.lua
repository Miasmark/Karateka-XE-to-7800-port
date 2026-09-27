-- which RAM is ever written: console RAM $1800-$27FF, the stack page
-- $0100-$01FF (lowest SP too) and cartridge RAM $4000-$7FFF outside the two
-- framebuffers; at the end (END, or when MAME stops) the written addresses
-- as a bitmap to ramuse.bin (the 64K space, one byte each: 1 = written) and
-- the lowest SP to ramuse.txt. WITHPLAY=1: playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local END = tonumber(os.getenv("END") or "15000")
local w = {}
local minsp = 0xFF
local FROM = tonumber(os.getenv("FROM") or "200")   -- after the BIOS and the power-on clear
local fnow = 0
local function tap(a, d) if fnow >= FROM then w[a] = true end; return d end
T1 = mem:install_write_tap(0x1800, 0x27FF, "cram", tap)
T2 = mem:install_write_tap(0x0100, 0x01FF, "stack", tap)
T3 = mem:install_write_tap(0x4000, 0x400F, "c0", tap)
T4 = mem:install_write_tap(0x57F8, 0x5807, "c1", tap)
T5 = mem:install_write_tap(0x6FF0, 0x7FFF, "c2", tap)
local f, done = 0, false
local function finish()
  if done then return end
  done = true
  local t = {}
  for a = 0, 0xFFFF do t[#t + 1] = w[a] and "\1" or "\0" end
  local o = io.open("ramuse.bin", "wb"); o:write(table.concat(t)); o:close()
  local p = io.open("ramuse.txt", "w"); p:write(string.format("lowest SP %02X\n", minsp)); p:close()
end
STOPR = emu.add_machine_stop_notifier(finish)
emu.register_frame_done(function()
  f = f + 1; fnow = f
  local sp = cpu.state["SP"].value & 0xFF
  if f >= FROM and sp < minsp then minsp = sp end
  if f >= END then finish(); M:exit() end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
