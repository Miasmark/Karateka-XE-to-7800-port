-- checks the fast fill (FINDINGS "The fast fill") against what the game's
-- loops do: for every rectangle fill ($2CCD) and pattern fill ($2D03) that
-- gets past its setup (at $2CE0 / $2D16: $14/$15 the first row's first
-- byte, $0D rows, $0E+1 bytes a row), the bytes written to the buffers
-- until it returns must be exactly the rectangle's, each with its final
-- value (rectangle: $02; pattern: rows counted down from $0D, odd $02, even
-- $12), and it must leave $14/$15 at the last row and Y = $FF. A fill into
-- RowBase's scratch row (below the bottom) must write no buffer byte.
-- From FROM to END, to fillcheck.log. WITHPLAY=1: playkey drives.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, SPs = cpu.state["PC"], cpu.state["SP"]
local FROM = tonumber(os.getenv("FROM") or "0")
local END = tonumber(os.getenv("END") or "6000")
local ZP = {}
for line in io.lines(os.getenv("ZPMAP")) do
  local z, t = line:match("^(%x+) (%x+)")
  if z then ZP[tonumber(z, 16)] = tonumber(t, 16) end
end
local function z(n) return mem:read_u8(ZP[n]) end
local RECT, PAT = 0x7CCD, 0x7D03            -- the entries
local RECT_GO, PAT_GO = 0x7CE0, 0x7D16      -- past the setup
local f, fill, writes = 0, nil, nil
local FAULT = os.getenv("FAULT")
local log = io.open("fillcheck.log", "w")
local st = {rect = 0, pat = 0, bad = 0, scratch = 0, zero = 0, bytes = 0}
W = mem:install_write_tap(0x4010, 0x6FEF, "fb", function(a, d)
  if writes then writes[a] = d end
  return d end)
T = mem:install_read_tap(0x0000, 0xFFFF, "fc", function(a, d)
  if a ~= PCs.value or f < FROM then return d end
  local sp = SPs.value & 0xFF
  if fill and fill.go and sp > fill.sp then          -- returned
    local want, n = {}, 0
    local p, h, w = fill.p, fill.h, fill.w
    local inbuf = p >= 0x4010 and p < 0x6FF0
    if inbuf then
      for i = 0, h - 1 do
        local v = fill.pat and (((h - i) % 2 == 1) and fill.v02 or fill.v12) or fill.v02
        for j = 0, w - 1 do want[p + 40 * i + j] = v; n = n + 1 end
        if FAULT and i == h - 1 then want[p + 40 * i] = (v + 1) & 0xFF end   -- a self-test: must be caught
      end
    else st.scratch = st.scratch + 1 end
    local ok, why = true, nil
    for addr, v in pairs(want) do
      if writes[addr] ~= v then ok = false; why = why or string.format("$%04X got %s want %02X", addr, writes[addr] and string.format("%02X", writes[addr]) or "none", v) end
    end
    for addr, v in pairs(writes) do
      if want[addr] == nil then ok = false; why = why or string.format("$%04X written %02X, outside", addr, v) end
    end
    local ptr = z(0x15) * 256 + z(0x14)
    local wantptr = p + 40 * (h - 1)
    if h > 0 and ptr ~= wantptr then ok = false; why = why or string.format("$14/$15 $%04X want $%04X", ptr, wantptr) end
    if cpu.state["Y"].value ~= 0xFF then ok = false; why = why or string.format("Y %02X", cpu.state["Y"].value) end
    if not ok then
      st.bad = st.bad + 1
      log:write(string.format("f%d %s at $%04X, %d rows x %d: %s\n", f, fill.pat and "pattern" or "fill", p, h, w, why))
    end
    st.bytes = st.bytes + n
    fill, writes = nil, nil
  end
  if a == RECT or a == PAT then
    fill = {sp = sp, pat = (a == PAT)}
  elseif fill and not fill.go and (a == RECT_GO or a == PAT_GO) then
    fill.go = true
    fill.p = z(0x15) * 256 + z(0x14)
    fill.h, fill.w = z(0x0D), z(0x0E) + 1
    fill.v02, fill.v12 = z(0x02), z(0x12)
    if fill.h == 0 then st.zero = st.zero + 1; log:write(string.format("f%d a fill of 0 rows at $%04X\n", f, fill.p)) end
    if fill.pat then st.pat = st.pat + 1 else st.rect = st.rect + 1 end
    writes = {}
  end
  return d end)
local done = false
local function report()
  if done then return end
  done = true
  log:write(string.format("frames %d-%d: %d rectangle fills, %d pattern fills (%d into the scratch row), %d bytes; %d wrong; %d of 0 rows\n",
    FROM, f, st.rect, st.pat, st.scratch, st.bytes, st.bad, st.zero))
  log:close()
end
STOP = emu.add_machine_stop_notifier(report)
emu.register_frame_done(function() f = f + 1; if f >= END then report(); M:exit() end end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
