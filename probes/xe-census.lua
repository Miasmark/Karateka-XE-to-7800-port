-- xe-census.lua -- Karateka XEGS (MAME `xegs`): what each scene writes, reads,
-- executes and does to the hardware. See FINDINGS.md, "Step 2" onwards.
--
-- Everything is keyed by the scene whose banks are in RAM: the loader reads
-- $D0 at $2F75 to pick the data bank and has finished copying at $2F84.
-- (Keying by $D0 itself misfiles the old scene's last instructions: the game
-- writes $D0 before the loader replaces the banks.)
--
-- Reads by the loader's copy loop ($B2CC-$B2EA) and the OS (PC >= $C000) are
-- ignored: their STA (zp),Y makes a dummy read of every destination byte.
-- Beware that ANTIC's DMA also appears as reads by whatever instruction is
-- running; the .rd map therefore includes display-list and screen fetches.
--
-- Env:
--   OUT       output prefix (default census)
--   END       stop at this frame (default 6000)
--   SCENE     substitute this scene for the game-start write of $D0 = 1
--             (1: no substitution)
--   PLAYBACK  set when replaying an .inp: no scripted input
--   CHEAT     a script to dofile() first (the one a recording was made with)
--
-- Output (one "key count" per line; key = scene*65536 + address, plus
-- window bank * 2^24 for $8000-$9FFF):
--   .wr  writes          .ex  instructions executed   .rd  bytes read
--   .hwr/.hww  hardware reads/writes ($D000-$D5FF)
--   .col  colour/DLIST writes: "scene frame line reg value"
--   .frames  frames per scene     .misc  lowest stack pointer

if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local SC = tonumber(os.getenv("SCENE") or "1")
local END = tonumber(os.getenv("END") or "6000")
local OUT = os.getenv("OUT") or "census"
local f, done, win = 0, false, 14
local wr, hwr, hww, ex, rd, frames = {}, {}, {}, {}, {}, {}
local col = {}
local minsp = 0xFF
local LOADED, PENDING = 0, 0
local function sc() return LOADED end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end

-- globals: a tap held only in a local is garbage-collected
XE_CENSUS = {
  mem:install_read_tap(0x00D0, 0x00D0, "c-ld-d0", function(a, d)
    if PCs.value == 0x2F75 then PENDING = d end
    return d end),
  mem:install_read_tap(0x2F84, 0x2F84, "c-ld-done", function(a, d)
    if PCs.value == 0x2F84 then LOADED = PENDING end
    return d end),
  mem:install_write_tap(0x00D0, 0x00D0, "c-sc", function(a, d)
    if not done and d == 1 and SC ~= 1 then done = true; return SC end
    return d end),
  mem:install_write_tap(0x0000, 0xBFFF, "c-w", function(a, d)
    local pc = PCs.value
    if pc >= 0xC000 or (pc >= 0xB2CC and pc <= 0xB2EA) then return d end
    bump(wr, sc() * 65536 + a)
    return d end),
  mem:install_write_tap(0xD000, 0xD5FF, "c-hw", function(a, d)
    if PCs.value >= 0xC000 then return d end
    local s = sc()
    bump(hww, s * 65536 + a)
    if a == 0xD500 then win = d & 0x0F end
    if (a >= 0xD016 and a <= 0xD01A) or a == 0xD402 or a == 0xD403 then
      col[#col + 1] = string.format("%d %d %d %04X %02X", s, f, mem:read_u8(0xD40B) * 2, a, d)
    end
    return d end),
  mem:install_read_tap(0xD000, 0xD4FF, "c-hr", function(a, d)
    if PCs.value < 0xC000 then bump(hwr, sc() * 65536 + a) end
    return d end),
  mem:install_read_tap(0x0480, 0xBFFF, "c-x", function(a, d)
    local pc = PCs.value
    local k = sc() * 65536 + a
    if a >= 0x8000 and a < 0xA000 then k = k + win * 16777216 end
    if pc < 0xC000 and not (pc >= 0xB2CC and pc <= 0xB2EA) then rd[k] = 1 end
    if a == pc then bump(ex, k) end
    return d end),
}

emu.register_frame_done(function()
  f = f + 1
  local sp = cpu.state["SP"].value & 0xFF
  if f > 100 and sp < minsp then minsp = sp end
  bump(frames, sc())
  if not os.getenv("PLAYBACK") and f > 1800 then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f >= END then
    local function dump(name, t)
      local o = io.open(OUT .. "." .. name, "w")
      for k, v in pairs(t) do o:write(string.format("%d %d\n", k, v)) end
      o:close()
    end
    dump("wr", wr); dump("hwr", hwr); dump("hww", hww); dump("ex", ex); dump("rd", rd); dump("frames", frames)
    local o = io.open(OUT .. ".col", "w"); o:write(table.concat(col, "\n")); o:close()
    o = io.open(OUT .. ".misc", "w"); o:write(string.format("minsp %02X\n", minsp)); o:close()
    M:exit()
  end
end)
