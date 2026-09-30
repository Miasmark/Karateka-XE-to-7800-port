-- both framebuffers, row by row (the XEGS order), at the end of the frame
-- after every buffer flip (a DPPH change), from flip FROMFLIP to TOFLIP, into
-- one file fbflips.bin (per flip: the flip number as 2 bytes, then A's 153
-- rows of 40 bytes, then B's), and the frame of each to fbflips.log.
-- LAYOUT=pages: the multi-line-zone layout (karateka-enh build7800.fb_row);
-- otherwise the stable build's (A $5808, B $4010, 40 bytes a row).
-- WITHPLAY=1 drives input with playkey.lua (its env applies). END frames.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local END = tonumber(os.getenv("END") or "9000")
local F0, F1 = tonumber(os.getenv("FROMFLIP") or "0"), tonumber(os.getenv("TOFLIP") or "100000")
local pages = os.getenv("LAYOUT") == "pages"
-- ATFRAMES=a,b,...: dump at the end of these frames instead of at flips
local at = {}
for n in (os.getenv("ATFRAMES") or ""):gmatch("%d+") do at[tonumber(n)] = true end
local f, flips, last, pend = 0, 0, nil, false
local out = io.open("fbflips.bin", "wb")
local log = io.open("fbflips.log", "w")
D = mem:install_write_tap(0x002C, 0x002C, "dpph", function(a, d)
  if last and d ~= last then flips = flips + 1; pend = true end
  last = d
  return d end)
local function row(buf, r)
  if pages then
    return (0x72 - r % 51) * 256 + 16 + 40 * (3 * buf + r // 51)
  end
  return (buf == 0 and 0x5808 or 0x4010) + 40 * r
end
local function dump()
  local t = {string.char(flips & 0xFF, flips >> 8)}
  for buf = 0, 1 do
    for r = 0, 152 do
      local at = row(buf, r)
      for i = 0, 39 do t[#t + 1] = string.char(mem:read_u8(at + i)) end
    end
  end
  out:write(table.concat(t))
end
emu.register_frame_done(function()
  f = f + 1
  if at[f] then dump(); log:write(string.format("frame %d flip %d\n", f, flips)); log:flush() end
  if pend then
    pend = false
    if next(at) == nil and flips >= F0 and flips <= F1 then dump(); log:write(string.format("flip %d frame %d\n", flips, f)); log:flush() end
  end
  if f >= END then out:close(); log:close(); M:exit() end
end)
STOP = emu.add_machine_stop_notifier(function() pcall(function() out:close(); log:close() end) end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
