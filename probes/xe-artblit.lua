-- xe-artblit.lua -- Karateka XEGS (MAME `xegs`): what the game touches while a
-- blit is reading the art, outside interrupts. Decides whether the 7800 can
-- page the art bank in for a blit (FINDINGS, "The banking layout").
--
-- A blit is the stretch from the header read at $29D8 to the pointer restore
-- at $29FB; it reads art when its source pointer ($03/$04) is in $8000-$9FFF.
-- Inside such a blit, every instruction's effective address is computed at
-- its fetch (never taken from observed reads: ANTIC's DMA shows up as reads)
-- and filed by region, together with where the code itself runs. Interrupts
-- are excluded (NMI entry through the OS vector to RTI).
-- Also counted: art read by instructions outside any such blit.
-- Env: OUT, END, SCENE, PLAYBACK, CHEAT as in xe-census.lua; OPT as in
-- xe-origin.lua.

if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
dofile(os.getenv("OPT"))
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, Xs, Ys = cpu.state["PC"], cpu.state["X"], cpu.state["Y"]
local END = tonumber(os.getenv("END") or "6000")
local SC = tonumber(os.getenv("SCENE") or "1")
local f, done = 0, false
local INNER = false
local function rd(a) INNER = true; local v = mem:read_u8(a & 0xFFFF); INNER = false; return v end
local NMI = rd(0xFFFA) + 256 * rd(0xFFFB)
local depth, inblit, artblit = 0, false, false
local touched, code, outside = {}, {}, {}
local function region(a)
  if a < 0x100 then return "zero page" elseif a < 0x200 then return "stack"
  elseif a < 0x480 then return "os ram" elseif a < 0x6E8 then return "sprites"
  elseif a < 0x1000 then return "common" elseif a < 0x1203 then return "engine"
  elseif a < 0x2300 then return "scene code" elseif a < 0x3000 then return "engine"
  elseif a < 0x6000 then return "framebuffer" elseif a < 0x8000 then return "scene data"
  elseif a < 0xA000 then return "art" elseif a < 0xC000 then return "bank 15"
  elseif a < 0xD000 then return "os" elseif a < 0xD800 then return "hardware" end
  return "os"
end
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end

XE_ARTBLIT = {
  mem:install_write_tap(0x00D0, 0x00D0, "ab-sc", function(a, d)
    if not done and d == 1 and SC ~= 1 then done = true; return SC end
    return d end),
  mem:install_read_tap(0x0480, 0xFFFF, "ab-fetch", function(a, d)
    if INNER then return d end
    local pc = PCs.value
    if a ~= pc then return d end
    if pc == NMI then depth = depth + 1 end
    if d == 0x40 and depth > 0 then depth = depth - 1; return d end
    if depth > 0 then return d end
    if pc == 0x29D8 then inblit = true; artblit = rd(0x04) >= 0x80 and rd(0x04) < 0xA0 end
    if pc == 0x29FB then inblit = false; artblit = false end
    if pc >= 0xC000 then return d end
    local mode = OPT[d][2]
    local x, y = Xs.value & 0xFF, Ys.value & 0xFF
    local ea = nil
    if mode == "zp" then ea = rd(pc + 1)
    elseif mode == "zpx" then ea = (rd(pc + 1) + x) & 0xFF
    elseif mode == "zpy" then ea = (rd(pc + 1) + y) & 0xFF
    elseif mode == "abs" then ea = rd(pc + 1) + 256 * rd(pc + 2)
    elseif mode == "abx" then ea = (rd(pc + 1) + 256 * rd(pc + 2) + x) & 0xFFFF
    elseif mode == "aby" then ea = (rd(pc + 1) + 256 * rd(pc + 2) + y) & 0xFFFF
    elseif mode == "izy" then local z = rd(pc + 1); ea = (rd(z) + 256 * rd((z + 1) & 0xFF) + y) & 0xFFFF
    elseif mode == "izx" then local z = (rd(pc + 1) + x) & 0xFF; ea = rd(z) + 256 * rd((z + 1) & 0xFF)
    end
    local mn = OPT[d][1]
    if mn == "JMP" or mn == "JSR" then ea = nil end      -- a jump target, not data
    if artblit then
      bump(code, region(pc))
      if ea then bump(touched, region(ea) .. (region(ea) == "common" and string.format(" $%04X by $%04X", ea, pc) or "")) end
    elseif ea and ea >= 0x8000 and ea < 0xA000 then
      bump(outside, string.format("$%04X", pc))
    end
    return d end),
}

emu.register_frame_done(function()
  f = f + 1
  if not os.getenv("PLAYBACK") and f > 1800 then
    local ph = f % 90
    press("P1 Right", ph < 40); press("P1 Button 1", ph >= 60 and ph < 64)
  end
  if f >= END then
    local o = io.open((os.getenv("OUT") or "artblit") .. ".txt", "w")
    for k, v in pairs(code) do o:write(string.format("code %s %d\n", k, v)) end
    for k, v in pairs(touched) do o:write(string.format("touch %s %d\n", k, v)) end
    for k, v in pairs(outside) do o:write(string.format("art-outside-blit %s %d\n", k, v)) end
    o:close(); M:exit()
  end
end)
