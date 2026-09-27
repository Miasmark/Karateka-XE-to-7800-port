-- a scripted player keyed on the game's own progress, for comparing the port
-- with the original: counts calls of $0862 (buffer flip and frame wait in the
-- title and story; on the 7800 at $9862) and of $B60F (the same in play) and, from flip K0 (default 170), holds right for flips
-- 0-12 of every 30 and presses fire at 20-21; dumps both framebuffers at
-- each flip in KEYN to fbk<N>.bin and logs $D0 there to playkey.log; stops
-- after the last, or after END frames (default 6000; the flip count every
-- 100 frames goes to the log). MACHINE=xe for the original.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local K = 0x0862 + (xe and 0 or 0x9000)
-- gameplay flips at bank 15's $B60F instead; on the 7800 at KEYB (from the
-- build's symbol file, K_B60F)
local KB = xe and 0xB60F or tonumber(os.getenv("KEYB") or "0", 16)
if not xe and KB == 0 then   -- from the build's symbol file
  dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
  KB = SYM_ADDR.K_B60F
end
local K0 = tonumber(os.getenv("K0") or "170")
local A, B = xe and 0x4808 or 0x5808, xe and 0x3010 or 0x4010
local ZD0 = xe and 0xD0 or tonumber(os.getenv("ZD0") or "D0", 16)
local want, last = {}, 0
for n in (os.getenv("KEYN") or "300"):gmatch("%d+") do want[tonumber(n)] = true; last = math.max(last, tonumber(n)) end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end
local n = 0
local log = io.open("playkey.log", "w")
-- ZPLOG: from flip ZPFROM on, the game's zero page (XEGS $00-$FF; on the
-- 7800 through the build's map, ZPMAP) at every flip, to zp.log
local ZMAP = {}
for z = 0, 255 do ZMAP[z] = z end
if not xe and os.getenv("ZPMAP") then
  for line in io.lines(os.getenv("ZPMAP")) do
    local z, t = line:match("^(%x+) (%x+)")
    if z then ZMAP[tonumber(z, 16)] = tonumber(t, 16) end
  end
end
local ZPFROM = tonumber(os.getenv("ZPFROM") or "-1")
-- KEYLOG=1: which address each counted flip was (from ZPFROM), to keys.log
KEYLOG = os.getenv("KEYLOG") and io.open("keys.log", "w") or nil
local zlog = ZPFROM >= 0 and io.open("zp.log", "w") or nil
-- ZW: a game zero-page byte (XEGS address, hex) whose writes are logged
-- with the flip, PC and value from flip ZPFROM on, to zw.log
if os.getenv("ZW") then
  local zw = io.open("zw.log", "w")
  local za = ZMAP[tonumber(os.getenv("ZW"), 16)]
  ZWT = mem:install_write_tap(za, za, "zw", function(a, d)
    if n >= ZPFROM then zw:write(string.format("flip %d PC=%04X <-%02X\n", n, PCs.value, d)); zw:flush() end
    return d end)
end
-- INJECT=1: rather than pressing MAME's inputs (latched at frame boundaries,
-- which fall at different points of the game on the two machines), feed
-- the stick and fire straight into the game's reads: XEGS PORTA ($D300) and
-- TRIG0 ($D010); 7800 SWCHA ($0280) and INPT4 ($0C), with SWCHB's left
-- difficulty bit forced to B (no quick-stick latch)
local INJECT = os.getenv("INJECT") ~= nil
local rightOn, fireOn = false, false
-- SHORT=1: fire for one flip, not two (the VBI times a press in frames: 20 or
-- more is the other move, and two flips straddle that on the slower machine)
local SHORT = os.getenv("SHORT") ~= nil
local FIREFLAG = os.getenv("FIREFLAG") ~= nil
if INJECT then
  if xe then
    IJ1 = mem:install_read_tap(0xD300, 0xD300, "ijs", function(a, d)
      return (d & 0xF0) | (rightOn and 0x07 or 0x0F) end)
    IJ2 = mem:install_read_tap(0xD010, 0xD010, "ijf", function(a, d)
      return fireOn and 0 or 1 end)
  else
    IJ1 = mem:install_read_tap(0x0280, 0x0280, "ijs", function(a, d)
      return (d & 0x0F) | (rightOn and 0x70 or 0xF0) end)
    IJ2 = mem:install_read_tap(0x000C, 0x000C, "ijf", function(a, d)
      return fireOn and (d & 0x7F) or (d | 0x80) end)
    IJ3 = mem:install_read_tap(0x0282, 0x0282, "ijd", function(a, d)
      return d & 0xBF end)
    -- the port reads RIOT once a frame into S_RSWCHA/B and the game's stick
    -- reads use that copy: inject there too, so the game sees the stick as it
    -- is when it reads, as on the XEGS
    dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
    -- (only once the cartridge runs: the BIOS uses that RAM too)
    if SYM_ADDR.S_RSWCHA then
      local cart = false
      IJ6 = mem:install_read_tap(SYM_ADDR.Reset, SYM_ADDR.Reset, "ijon", function(a, d)
        if a == PCs.value then cart = true end
        return d end)
      IJ4 = mem:install_read_tap(SYM_ADDR.S_RSWCHA, SYM_ADDR.S_RSWCHA, "ijsa", function(a, d)
        if not cart then return d end
        return (d & 0x0F) | (rightOn and 0x70 or 0xF0) end)
      IJ5 = mem:install_read_tap(SYM_ADDR.S_RSWCHB, SYM_ADDR.S_RSWCHB, "ijsb", function(a, d)
        if not cart then return d end
        return d & 0xBF end)
    end
  end
end
-- A flip counts when its instruction runs: MAME fetches the opcode, and if
-- an interrupt is taken there, fetches it again after the RTI; so a key
-- fetch only arms the count, and the next fetch confirms it when it is the
-- instruction's successor ($0862 JSR $0878: $0878, +$16; $B60F LDA abs: +3)
-- SCENE: substitute this scene for the game-start write of $D0 = 1 (as the
-- census does), to reach scenes 2, 3, 4 and 6 directly
local SCENE = tonumber(os.getenv("SCENE") or "1")
local subst = false
if SCENE ~= 1 then
  SC = mem:install_write_tap(ZD0, ZD0, "scene", function(a, d)
    if not subst and d == 1 then
      subst = true
      -- HANDOVER=1: also what the previous scene's handover sets (scene 3's
      -- end, for scene 4: $0AFC=$AA, $0AFE=$FF, $B0=8; FINDINGS "The
      -- princess room"); on the 7800 through the carve map
      if os.getenv("HANDOVER") then
        local afc = xe and 0x0AFC or 0x1A86
        mem:write_u8(afc, 0xAA); mem:write_u8(afc + 2, 0xFF); mem:write_u8(ZMAP[0xB0], 8)
      end
      return SCENE
    end
    return d end)
end
local armed = nil
local function key(a, d)
  if a ~= PCs.value then return d end
  armed = a
  return d
end
-- SNAPK: flips (comma list) at which to take a screenshot
local SNAPK = {}
for k in (os.getenv("SNAPK") or ""):gmatch("%d+") do SNAPK[tonumber(k)] = true end
local function counted(a, d)
  n = n + 1
  if SNAPK[n] then M.video:snapshot() end
  PLAYKEY_N = n
  if KEYLOG and n >= ZPFROM then
    -- with the frame-pacing bytes $0AFC-$0AFE (carved to $1A86 on the 7800)
    -- and the buffer select $07
    local P = xe and 0x0AFC or 0x1A86
    KEYLOG:write(string.format("flip %d at %04X SP=%02X AFC-E=%02X %02X %02X 07=%02X\n", n, a,
      cpu.state["SP"].value & 0xFF, mem:read_u8(P), mem:read_u8(P + 1), mem:read_u8(P + 2), mem:read_u8(ZMAP[7])))
    KEYLOG:flush()
  end
  if n >= K0 then
    local ph = (n - K0) % 30
    rightOn, fireOn = ph <= 12, ph == 20 or (ph == 21 and not SHORT)
    if FIREFLAG then
      -- FIREFLAG=1: the press as the game's own short-press flag ($47, which its
      -- VBI sets from the trigger), set as the flip starts on both machines, so
      -- where each machine's VBI falls against the main loop cannot matter; the
      -- trigger itself stays up
      if ph == 20 and mem:read_u8(ZMAP[0x46]) ~= 0xFF then mem:write_u8(ZMAP[0x47], 0xFF) end
      fireOn = false
    end
    if not INJECT then press("P1 Right", rightOn); press("P1 Button 1", fireOn) end
  end
  if zlog and n >= ZPFROM then
    local t = {}
    for z = 0, 255 do t[#t + 1] = string.format("%02X", mem:read_u8(ZMAP[z])) end
    zlog:write(n .. " " .. table.concat(t, " ") .. "\n"); zlog:flush()
  end
  if want[n] then
    local o = io.open(string.format("fbk%d.bin", n), "wb")
    for _, base in ipairs({A, B}) do
      local t = {}
      for i = 0, 0x17E7 do t[#t + 1] = string.char(mem:read_u8(base + i)) end
      o:write(table.concat(t))
    end
    o:close()
    log:write(string.format("flip %d D0=%02X\n", n, mem:read_u8(ZD0)))
    log:flush()
    if n >= last then log:close(); M:exit() end
  end
  return d end
T = mem:install_read_tap(K, K, "key", key)
TB = mem:install_read_tap(KB, KB, "keyb", key)
TN = mem:install_read_tap(0x0000, 0xFFFF, "keynext", function(a, d)
  if armed == nil or a ~= PCs.value or a == armed then return d end
  local k = armed
  armed = nil
  -- (the enhancement fork puts a JSR at $B60F: its target confirms too)
  local kbjsr = (mem:read_u8(KB) == 0x20) and (mem:read_u8(KB + 1) + mem:read_u8(KB + 2) * 256) or nil
  if (k == K and a == K + 0x16) or (k == KB and (a == KB + 3 or a == kbjsr)) then return counted(k, d) end
  return d end)
local END = tonumber(os.getenv("END") or "6000")
local SNAPAT = tonumber(os.getenv("SNAPAT") or "-1")   -- a snapshot at this frame
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f % 100 == 0 then
    log:write(string.format("f%d flips %d D0=%02X PC=%04X SP=%02X\n", f, n, mem:read_u8(ZD0), PCs.value,
      cpu.state["SP"].value & 0xFF))
    log:flush()
  end
  if SNAPAT and f == SNAPAT then M.video:snapshot() end
  if f >= END then log:close(); M:exit() end
end)
