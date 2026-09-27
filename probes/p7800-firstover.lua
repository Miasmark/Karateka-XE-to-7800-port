-- the first game write past framebuffer A ($6FF0-$6FFF) after frame FROM:
-- the last N instruction fetches before it (PC:opcode, SP, bank, label) and
-- zero page $00-$FF at that moment; to firstover.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local N = tonumber(os.getenv("N") or "3000")
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local ring, n, f, done = {}, 0, 0, false
-- EXCL: fetch ranges left out of the ring, e.g. "7900-79FF,E1C4-E269"
local excl = {}
for lo, hi in (os.getenv("EXCL") or ""):gmatch("(%x+)-(%x+)") do excl[#excl + 1] = {tonumber(lo, 16), tonumber(hi, 16)} end
local o = io.open("firstover.log", "w")
TC = mem:install_read_tap(0x0000, 0xFFFF, "ring", function(a, d)
  if done or f < FROM or a ~= PCs.value then return d end
  for _, r in ipairs(excl) do if a >= r[1] and a <= r[2] then return d end end
  n = n + 1
  ring[(n - 1) % N + 1] = string.format("f%d %04X:%02X S%02X b%d %s", f, a, d, SPs.value & 0xFF, mem:read_u8(S.S_BANK), SYM_NAME[a] or "")
  return d end)
-- WLO/WHI (hex): watch this range instead (default $6FF0-$6FFF); BLITONLY=1:
-- only writes by the blitter's stores ($7927/$7946)
local WLO = tonumber(os.getenv("WLO") or "6FF0", 16)
local WHI = tonumber(os.getenv("WHI") or "6FFF", 16)
local BLITONLY = os.getenv("BLITONLY") ~= nil
TW = mem:install_write_tap(WLO, WHI, "ov", function(a, d)
  if done or f < FROM then return d end
  local pc = PCs.value
  if pc >= 0xE000 then return d end
  if BLITONLY and pc ~= 0x7927 and pc ~= 0x7946 then return d end
  done = true
  o:write(string.format("first watched write: frame %d PC=%04X %04X<-%02X\n", f, pc, a, d))
  for i = math.max(1, n - N + 1), n do o:write(ring[(i - 1) % N + 1] .. "\n") end
  local sp, t = SPs.value & 0xFF, {}
  for i = sp + 1, 0xFF do t[#t + 1] = string.format("%02X", mem:read_u8(0x100 + i)) end
  o:write(string.format("stack from $%03X: %s\n", 0x100 + sp + 1, table.concat(t, " ")))
  o:write("zero page:\n")
  for r = 0, 15 do
    local t = {}
    for c = 0, 15 do t[#t + 1] = string.format("%02X", mem:read_u8(r * 16 + c)) end
    o:write(string.format("%02X: %s\n", r * 16, table.concat(t, " ")))
  end
  o:close()
  return d end)
local function finish()
  if not done then done = true; o:write(string.format("no overrun (to frame %d)\n", f)); o:close() end
end
emu.register_frame_done(function()
  f = f + 1
  if f >= END then finish(); M:exit() end
end)
-- playkey.lua may end the run first
STOPPER = emu.add_machine_stop_notifier(finish)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
