-- checks the column routine (ColA, FINDINGS "The tiny sprites are columns")
-- against a model of the game's blitter A in its store mode:
--  1. every real blitter A call in store mode ($0F 1-$7F): the model, run on
--     the buffer as it was at the call, must give what the blitter wrote
--     (this checks the model);
--  2. every ColA call: the model, run piece by piece from the buffer as it
--     was at ColA's entry, must give the buffer ColA left, and $06 the last
--     piece's row.
-- Also counts ColA's paths (the copy, nothing to draw, the game's way) and
-- blitter C columns (Col68). From FROM to END, to colcheck.log. WITHPLAY=1:
-- playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local BLITA, SETUP = 0x784E, 0x7857          -- $284E, and $2857 (header read, bank in)
local FBA, FBB, ROWS = 0x5808, 0x4010, 153
local MASK1 = {[0] = 0x00, 0xC0, 0xF0, 0xFC}
local MASK2 = {[0] = 0xFF, 0x3F, 0x0F, 0x03}
local f = 0
local FAULT = os.getenv("FAULT")
local log = io.open("colcheck.log", "w")
local stats = {blits = 0, blitbad = 0, cols = 0, colbad = 0, copy = 0, none = 0, plain = 0, c68 = 0, pieces = 0}

local function base() return (z(0x07) == 0x20) and FBB or FBA end
local function snap(b)
  local t = {}
  for i = 0, 40 * ROWS - 1 do t[i] = mem:read_u8(b + i) end
  return t
end

-- the model: one store-mode blit of `data` (rows of bytes) into buffer t
local function model(t, p)
  local C, W, H, sh = p.C, p.W, p.H, p.sh
  local col0, skip, vis
  if C < 0x80 then
    if C >= 40 then return end
    col0, skip, vis = C, 0, math.min(W, 40 - C)
  else
    if C + W < 256 then return end
    col0, skip, vis = 0, 256 - C, (C + W) & 0xFF
  end
  local r = (p.R - 35) & 0xFF
  if r >= ROWS then return end
  local rows = math.min(H, ROWS - r)
  local edge = (((C + W) & 0xFF) < 40) or vis == 0
  local function sh_out(b) return b >> (2 * sh), (b << (8 - 2 * sh)) & 0xFF end
  for h = 0, rows - 1 do
    local a = 40 * (r + h) + col0
    local carry
    if skip > 0 then
      local _, c = sh_out(p.data[h][skip - 1]); carry = sh == 0 and 0 or c
    else carry = t[a] & MASK1[sh] end
    for j = 0, vis - 1 do
      local o, c = sh_out(p.data[h][skip + j])
      if sh == 0 then c = 0 end
      t[a + j] = o ~ carry
      carry = c
    end
    if edge then t[a + vis] = (t[a + vis] & MASK2[sh]) | carry end
    if FAULT and vis > 1 then t[a + 1] = t[a + 1] ~ 0x01 end   -- a self-test: must be caught
  end
end

local function readparams()        -- at $2857: the bank is in, $03/$04 past the header
  local src = z(0x04) * 256 + z(0x03)
  local p = {C = z(0x05), R = z(0x06), H = z(0x0D), W = z(0x0E), sh = z(0x10) >> 1, mode = z(0x0F), data = {}}
  for h = 0, p.H - 1 do
    p.data[h] = {}
    for j = 0, p.W - 1 do p.data[h][j] = mem:read_u8(src + h * p.W + j) end
  end
  return p
end

local function compare(t, b, what)
  local bad, first = 0, nil
  for i = 0, 40 * ROWS - 1 do
    if mem:read_u8(b + i) ~= t[i] then bad = bad + 1; first = first or i end
  end
  if bad > 0 then
    log:write(string.format("f%d %s: %d bytes differ, first row %d col %d (got %02X want %02X)\n",
      f, what, bad, first // 40, first % 40, mem:read_u8(b + first), t[first]))
  end
  return bad == 0
end

local blit = nil          -- the real blit in progress: {sp, before, p}
local col = nil           -- the ColA call in progress: {sp, before, lim, pieces}
T = mem:install_read_tap(0x0000, 0xFFFF, "cc", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  local sp = SPs.value & 0xFF
  if blit and sp > blit.sp then          -- the blit returned
    if blit.p and blit.p.mode >= 1 and blit.p.mode < 0x80 then
      model(blit.before, blit.p)
      stats.blits = stats.blits + 1
      if not compare(blit.before, blit.b, string.format("blit C=%d R=%d %dx%d sh %d", blit.p.C, blit.p.R, blit.p.H, blit.p.W, blit.p.sh)) then
        stats.blitbad = stats.blitbad + 1
      end
    end
    blit = nil
  end
  if col and sp > col.sp then            -- ColA returned
    stats.cols = stats.cols + 1
    local t = col.before
    local R = col.R0
    local last
    repeat
      R = (R + 2) & 0xFF
      col.p.R = R
      model(t, col.p)
      last = R
      stats.pieces = stats.pieces + 1
    until R >= col.lim
    local ok = compare(t, col.b, string.format("column lim %02X from %d C=%d %dx%d sh %d", col.lim, col.R0, col.p.C, col.p.H, col.p.W, col.p.sh))
    if z(0x06) ~= last then ok = false; log:write(string.format("f%d column: $06 %d, want %d\n", f, z(0x06), last)) end
    if not ok then stats.colbad = stats.colbad + 1 end
    col = nil
  end
  if a == BLITA and not blit then
    blit = {sp = sp, b = base()}
    blit.before = snap(blit.b)
  elseif a == SETUP and blit and not blit.p then
    blit.p = readparams()
    if col and not col.p then col.p = blit.p end
  elseif a == S.ColA and not col and mem:read_u8(ZP[0xD0]) ~= 0 then
    col = {sp = sp, b = base(), lim = cpu.state["A"].value, R0 = z(0x06)}
    col.before = snap(col.b)
  elseif a == S.ColC then stats.c68 = stats.c68 + 1
  elseif a == S.ColPlain then stats.plain = stats.plain + 1
  elseif a == S.ColTNone then stats.none = stats.none + 1
  elseif a == S.ColTEnd then stats.copy = stats.copy + 1
  end
  return d end)

local done = false
local function report()
  if done then return end
  done = true
  log:write(string.format("frames %d-%d: %d store-mode blits checked, %d wrong; %d columns checked, %d wrong\n",
    FROM, f, stats.blits, stats.blitbad, stats.cols, stats.colbad))
  log:write(string.format("column paths: %d copied, %d nothing to draw, %d the game's way; %d pieces; %d blitter C column pieces\n",
    stats.copy, stats.none, stats.plain, stats.pieces, stats.c68))
  log:close()
end
STOP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function() f = f + 1; if f >= END then report(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
