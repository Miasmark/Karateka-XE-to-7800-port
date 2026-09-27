-- xe-blitsrc.lua -- Karateka XEGS (MAME `xegs`): every byte read through the
-- blitter's source pointer ($03/$04), per loaded scene. Decides which scene
-- bytes must sit outside $8000-$9FFF in the 7800 scene page (the art bank's
-- range): the blit's bank is chosen from the source pointer's high byte.
--
-- The address is computed at the instruction fetch (LDA ($03),Y and friends:
-- any (zp),Y read with zp = $03), not taken from observed reads, because
-- ANTIC's DMA shows up as reads in the middle of CPU instructions.
-- Env: OUT, END, SCENE, PLAYBACK, CHEAT as in xe-census.lua.
-- Output OUT.src: "key count", key = scene*65536 + address.

if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, Ys = cpu.state["PC"], cpu.state["Y"]
local END = tonumber(os.getenv("END") or "6000")
local SC = tonumber(os.getenv("SCENE") or "1")
local f, done = 0, false
local LOADED, PENDING = 0, 0
local INNER = false
local src = {}
-- (zp),Y opcodes that read memory
local READS = {[0xB1] = true, [0x11] = true, [0x31] = true, [0x51] = true, [0x71] = true,
               [0xD1] = true, [0xF1] = true, [0xB3] = true}
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end

XE_BLITSRC = {
  mem:install_write_tap(0x00D0, 0x00D0, "b-sc", function(a, d)
    if not done and d == 1 and SC ~= 1 then done = true; return SC end
    return d end),
  mem:install_read_tap(0x00D0, 0x00D0, "b-ld-d0", function(a, d)
    if not INNER and PCs.value == 0x2F75 then PENDING = d end
    return d end),
  mem:install_read_tap(0x2F84, 0x2F84, "b-ld-done", function(a, d)
    if not INNER and PCs.value == 0x2F84 then LOADED = PENDING end
    return d end),
  mem:install_read_tap(0x0480, 0xBFFF, "b-fetch", function(a, d)
    if INNER then return d end
    local pc = PCs.value
    if a ~= pc or not READS[d] or pc >= 0xC000 then return d end
    INNER = true
    local z = mem:read_u8(pc + 1)
    local ea = nil
    if z == 0x03 then ea = (mem:read_u8(0x03) + 256 * mem:read_u8(0x04) + (Ys.value & 0xFF)) & 0xFFFF end
    INNER = false
    if ea then local k = LOADED * 65536 + ea; src[k] = (src[k] or 0) + 1 end
    return d end),
}

emu.register_frame_done(function()
  f = f + 1
  if not os.getenv("PLAYBACK") and f > 1800 then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f >= END then
    local o = io.open((os.getenv("OUT") or "blitsrc") .. ".src", "w")
    for k, v in pairs(src) do o:write(string.format("%d %d\n", k, v)) end
    o:close(); M:exit()
  end
end)
