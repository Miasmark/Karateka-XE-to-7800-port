-- xe-origin.lua -- Karateka XEGS (MAME `xegs`): which bytes of the original
-- hold addresses? See FINDINGS.md, "Finding the addresses stored in data".
--
-- Follows every loaded value back to the byte it came from (register
-- transfers, arithmetic, stores to RAM, pushes) and, when a value is used as
-- an address, records the origins of its high and low halves:
--   ptr      (zp),Y / (zp,X) pointers
--   jmpind   JMP (vector)
--   rts      RTS to an address pushed with PHA, not by JSR
--   selfmod  an absolute operand that was written at run time
-- Effective addresses are computed from the opcode, its operand bytes and
-- X/Y/SP at the instruction fetch, never taken from observed reads: MAME
-- routes ANTIC's DMA through the same address space, so a read tap sees
-- display-list and screen fetches in the middle of CPU instructions.
-- Origins in the scene-specific ranges are keyed by the loaded scene
-- (scene*65536 + address).
--
-- Env: OUT, END, SCENE, PLAYBACK, CHEAT as in xe-census.lua;
--      OPT = path of optable.lua (port/mkoptable.py).
-- Output OUT.txt: "kind pc hi lo count target_min target_max" per line.

if os.getenv("CHEAT") then dofile(os.getenv("CHEAT")) end
dofile(os.getenv("OPT"))
local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, Xs, Ys, SPs = cpu.state["PC"], cpu.state["X"], cpu.state["Y"], cpu.state["SP"]
local END = tonumber(os.getenv("END") or "6000")
local SC = tonumber(os.getenv("SCENE") or "1")
local f, done = 0, false
local LOADED, PENDING = 0, 0
local JSRM, INTM = -1, -2
local memsrc = {}
local srcA, srcX, srcY = nil, nil, nil
local cur = nil
local uses = {}
local INNER = false
local function rd(a) INNER = true; local v = mem:read_u8(a & 0xFFFF); INNER = false; return v end
local function scenespecific(a) return (a >= 0x1203 and a < 0x2300) or (a >= 0x24A5 and a < 0x24AC) or (a >= 0x6000 and a < 0x8000) end
local function key(a) if scenespecific(a) then return LOADED * 65536 + a end return a end
local function orig(a) local m = memsrc[a]; if m ~= nil then return m end return key(a) end
local function skip(pc) return pc >= 0xC000 or (pc >= 0xB2CC and pc <= 0xB2EA) end
local function use(kind, pc, hi, lo, target)
  if hi == nil or lo == nil or hi < 0 or lo < 0 or target == nil then return end
  local k = string.format("%s %04X %d %d", kind, pc, hi, lo)
  local u = uses[k]
  if not u then u = {n = 0, lo = target, hi = target}; uses[k] = u end
  u.n = u.n + 1
  if target < u.lo then u.lo = target end
  if target > u.hi then u.hi = target end
end
local function start(pc, op)
  local mn, mode = OPT[op][1], OPT[op][2]
  local c = {op = op, mn = mn, mode = mode, pc = pc, sp = SPs.value & 0xFF}
  local x, y = Xs.value & 0xFF, Ys.value & 0xFF
  if mode == "imm" then c.ea = pc + 1
  elseif mode == "zp" then c.ea = rd(pc + 1)
  elseif mode == "zpx" then c.ea = (rd(pc + 1) + x) & 0xFF
  elseif mode == "zpy" then c.ea = (rd(pc + 1) + y) & 0xFF
  elseif mode == "abs" then c.ea = rd(pc + 1) + 256 * rd(pc + 2)
  elseif mode == "abx" then c.ea = (rd(pc + 1) + 256 * rd(pc + 2) + x) & 0xFFFF
  elseif mode == "aby" then c.ea = (rd(pc + 1) + 256 * rd(pc + 2) + y) & 0xFFFF
  elseif mode == "izy" then local z = rd(pc + 1); c.zp = z; c.ea = (rd(z) + 256 * rd((z + 1) & 0xFF) + y) & 0xFFFF
  elseif mode == "izx" then local z = (rd(pc + 1) + x) & 0xFF; c.zp = z; c.ea = rd(z) + 256 * rd((z + 1) & 0xFF)
  elseif mode == "ind" then c.vec = rd(pc + 1) + 256 * rd(pc + 2)
  end
  return c
end
local function finalize(c, nextpc)
  local mn, mode = c.mn, c.mode
  if mn == "LDA" or mn == "LAX" then srcA = orig(c.ea); if mn == "LAX" then srcX = srcA end
  elseif mn == "LDX" then srcX = orig(c.ea)
  elseif mn == "LDY" then srcY = orig(c.ea)
  elseif mn == "PLA" then srcA = orig(0x100 + ((c.sp + 1) & 0xFF))
  elseif mn == "TAX" then srcX = srcA elseif mn == "TAY" then srcY = srcA
  elseif mn == "TXA" then srcA = srcX elseif mn == "TYA" then srcA = srcY end
  if mode == "izy" or mode == "izx" then
    use("ptr", c.pc, orig((c.zp + 1) & 0xFF), orig(c.zp), c.ea)
  elseif mode == "ind" then
    use("jmpind", c.pc, orig(c.vec + 1), orig(c.vec), nextpc)
  elseif mn == "RTS" then
    local lo, hi = orig(0x100 + ((c.sp + 1) & 0xFF)), orig(0x100 + ((c.sp + 2) & 0xFF))
    if hi ~= JSRM and lo ~= JSRM and hi ~= INTM and lo ~= INTM then use("rts", c.pc, hi, lo, nextpc) end
  elseif mode == "abs" or mode == "abx" or mode == "aby" then
    if memsrc[c.pc + 1] ~= nil or memsrc[c.pc + 2] ~= nil then
      local target = (mn == "JMP" or mn == "JSR") and nextpc or c.ea
      use("selfmod", c.pc, orig(c.pc + 2), orig(c.pc + 1), target)
    end
  end
end
local fields = {}
for _, port in pairs(M.ioport.ports) do for name, fld in pairs(port.fields) do fields[name] = fld end end
local function press(n, on) if fields[n] then fields[n]:set_value(on and 1 or 0) end end

-- globals: a tap held only in a local is garbage-collected
XE_ORIGIN = {
  mem:install_write_tap(0x00D0, 0x00D0, "o-sc", function(a, d)
    if not done and d == 1 and SC ~= 1 then done = true; return SC end
    return d end),
  mem:install_read_tap(0x00D0, 0x00D0, "o-ld-d0", function(a, d)
    if not INNER and PCs.value == 0x2F75 then PENDING = d end
    return d end),
  mem:install_read_tap(0x2F84, 0x2F84, "o-ld-done", function(a, d)
    if not INNER and PCs.value == 0x2F84 then LOADED = PENDING end
    return d end),
  mem:install_read_tap(0x0480, 0xBFFF, "o-fetch", function(a, d)
    if INNER then return d end
    local pc = PCs.value
    if a ~= pc or skip(pc) then return d end
    if cur then finalize(cur, pc) end
    cur = start(pc, d)
    return d end),
  mem:install_write_tap(0x0000, 0xBFFF, "o-w", function(a, d)
    local pc = PCs.value
    if skip(pc) or not cur then return d end
    local mn = cur.mn
    if a >= 0x100 and a < 0x200 and a ~= cur.ea then
      if mn == "PHA" then memsrc[a] = srcA
      elseif mn == "JSR" then memsrc[a] = JSRM
      elseif mn == "PHP" then memsrc[a] = nil
      else memsrc[a] = INTM end                -- an interrupt's pushes
    elseif mn == "STA" or mn == "PHA" then memsrc[a] = srcA
    elseif mn == "STX" then memsrc[a] = srcX
    elseif mn == "STY" then memsrc[a] = srcY
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
    local o = io.open((os.getenv("OUT") or "origin") .. ".txt", "w")
    for k, u in pairs(uses) do o:write(string.format("%s %d %04X %04X\n", k, u.n, u.lo, u.hi)) end
    o:close(); M:exit()
  end
end)
