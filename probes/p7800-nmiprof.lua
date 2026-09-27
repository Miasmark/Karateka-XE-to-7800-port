-- where the NMI's cycles go: every instruction from the NMI's entry (Nmi)
-- to its final RTI (the one after NmiDone), in 6502 cycles (base counts, +1
-- for a taken branch; page crossings not counted, so slightly low), charged
-- to the nearest system label at or below the PC (fixed bank $E000 up) or
-- to the game's code by region: the engine (cart RAM $7000-$7FFF, the DLI
-- handler at $7026), the scene page ($8000-$BFFF, the vertical-blank handler
-- at $9F18), bank 15 ($C000-$E0D9). Per frame, averaged over FROM..END; also
-- the NMIs and game DLIs/VBIs per frame. To nmiprof.log. WITHPLAY=1: playkey
-- drives the input (its env applies).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "4000")
local CYC = {7,6,0,8,3,3,5,5,3,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,3,2,2,2,3,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,6,6,0,8,3,3,5,5,4,2,2,2,5,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,6,0,6,4,4,4,4,2,5,2,5,5,5,5,5,2,6,2,6,3,3,3,3,2,2,2,2,4,4,4,4,2,5,0,5,4,4,4,4,2,4,2,4,4,4,4,4,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7,2,6,2,8,3,3,5,5,2,2,2,2,4,4,6,6,2,5,0,8,4,4,6,6,2,4,2,7,4,4,7,7}
-- the system's code labels, sorted, for "nearest label at or below"
local labels = {}
for a, n in pairs(SYM_NAME) do
  if a >= 0xE0DA and a < 0xFFFA and not n:match("^S_") and not n:match("^SP_") then labels[#labels + 1] = a end
end
table.sort(labels)
local function owner(pc)
  if pc >= 0x7000 and pc < 0x8000 then return pc >= 0x7026 and pc < 0x7040 and "game DLI entry" or "game: engine" end
  if pc >= 0x8000 and pc < 0xC000 then return "game: scene page" end
  if pc < 0xE0DA then return pc >= 0xC000 and "game: bank 15" or string.format("other $%04X", pc) end
  local lo, hi = 1, #labels
  if pc < labels[1] then return "?" end
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if labels[mid] <= pc then lo = mid else hi = mid - 1 end
  end
  return SYM_NAME[labels[lo]]
end
-- the final RTI: the first $40 at or after NmiDone, found once the cartridge
-- is mapped (at script load it is not)
local final = nil
local function find_final()
  final = S.NmiQuit or S.NmiDone   -- the one RTI every NMI leaves by
  while mem:read_u8(final) ~= 0x40 do final = final + 1 end
end
local depth, f, frames = 0, 0, 0
local finals = 0
local by, nmis, total, main = {}, 0, 0, 0
local lastpc, lastop = -1, 0
local BR = {[0x10]=1, [0x30]=1, [0x50]=1, [0x70]=1, [0x90]=1, [0xB0]=1, [0xD0]=1, [0xF0]=1}
T = mem:install_read_tap(0x0000, 0xFFFF, "prof", function(a, d)
  if a ~= PCs.value then return d end
  if f < FROM then lastpc = -1; return d end
  if not final then find_final() end
  if a == S.Nmi then depth = depth + 1; nmis = nmis + 1 end
  local c = CYC[d + 1]
  if lastpc >= 0 and BR[lastop] and a ~= lastpc + 2 then c = c + 0 end
  if depth > 0 then
    local k = owner(a)
    -- a taken branch costs one more: charged to the branch's owner
    if lastpc >= 0 and BR[lastop] and a ~= ((lastpc + 2) & 0xFFFF) then by[owner(lastpc)] = (by[owner(lastpc)] or 0) + 1; total = total + 1 end
    by[k] = (by[k] or 0) + c
    total = total + c
    if a == final then depth = depth - 1; finals = finals + 1 end
  else
    main = main + c
  end
  lastpc, lastop = a, d
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > FROM then frames = frames + 1 end
  if f >= END then
    local o = io.open("nmiprof.log", "w")
    o:write(string.format("frames %d-%d, scene %d: NMI %.0f cycles a frame (%d NMIs, %.2f a frame); main program %.0f; final RTIs %d, depth now %d\n",
      FROM, END, mem:read_u8(0xD0), total / frames, nmis, nmis / frames, main / frames, finals, depth))
    local t = {}
    for k, v in pairs(by) do t[#t + 1] = {k, v} end
    table.sort(t, function(x, y) return x[2] > y[2] end)
    for _, kv in ipairs(t) do
      if kv[2] / frames >= 1 then o:write(string.format("  %-22s %6.0f  (%4.1f%%)\n", kv[1], kv[2] / frames, 100 * kv[2] / total)) end
    end
    o:close(); M:exit()
  end
end)
if os.getenv("WITHPLAY") then dofile(os.getenv("PROBES") .. "/playkey.lua") end
