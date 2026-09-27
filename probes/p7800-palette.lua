-- every frame's palette writes (MARIA $20-$3F except WSYNC $24, MSTAT $28,
-- DPPH $2C, DPPL $30, CHBASE $34, CTRL $3C) as "nmi#:reg=value", keyed by the
-- system's NMI count at the time; counts each distinct frame pattern and logs
-- frames whose pattern is rare. playkey.lua drives the input. To palette.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local FROM = tonumber(os.getenv("FROM") or "3000")
local END = tonumber(os.getenv("END") or "5000")
local skip = {[0x24] = true, [0x28] = true, [0x2C] = true, [0x30] = true, [0x34] = true, [0x3C] = true, [0x38] = true}
local f, cur = 0, {}
local frames = {}
PW = mem:install_write_tap(0x0020, 0x003F, "pal", function(a, d)
  if f >= FROM and not skip[a] then
    cur[#cur + 1] = string.format("%d:%02X=%02X", mem:read_u8(S.S_NMICOUNT), a, d)
  end
  return d end)
emu.register_frame_done(function()
  f = f + 1
  if f > FROM then frames[#frames + 1] = {f, table.concat(cur, " "), PLAYKEY_N or 0} end
  cur = {}
  if f >= END then
    local count = {}
    for _, fr in ipairs(frames) do count[fr[2]] = (count[fr[2]] or 0) + 1 end
    local o = io.open("palette.log", "w")
    local pats = {}
    for p, c in pairs(count) do pats[#pats + 1] = {p, c} end
    table.sort(pats, function(x, y) return x[2] > y[2] end)
    o:write(string.format("%d frames, %d distinct patterns\n", #frames, #pats))
    for i, pc in ipairs(pats) do
      o:write(string.format("pattern %d x%d: %s\n", i, pc[2], pc[1]))
      if i >= 12 then break end
    end
    o:write("rare frames (pattern seen <= 3 times):\n")
    for _, fr in ipairs(frames) do
      if count[fr[2]] <= 3 then o:write(string.format("f%d flip %d: %s\n", fr[1], fr[3], fr[2])) end
    end
    o:close(); M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
