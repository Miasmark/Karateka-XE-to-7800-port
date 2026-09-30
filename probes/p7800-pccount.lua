-- how many times each PC in PCS (name=hex,...) runs per frame, FROM-END: a
-- histogram per name (runs a frame -> frames); to pccount.log
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local FROM, END = tonumber(os.getenv("FROM") or "0"), tonumber(os.getenv("END") or "300")
local want, names, cnt, hist = {}, {}, {}, {}
for name, h in (os.getenv("PCS") or ""):gmatch("(%w+)=(%x+)") do
  local a = tonumber(h, 16); want[a] = name; names[#names + 1] = name; cnt[name] = 0; hist[name] = {}
end
local f = 0
TAPS = {}  -- global: taps only live while referenced
for a, name in pairs(want) do
  TAPS[#TAPS + 1] = mem:install_read_tap(a, a, "pc" .. name, function(ad, d)
    if f >= FROM and ad == PCs.value then cnt[name] = cnt[name] + 1 end
    return d end)
end
emu.register_frame_done(function()
  if f >= FROM then
    for _, n in ipairs(names) do hist[n][cnt[n]] = (hist[n][cnt[n]] or 0) + 1; cnt[n] = 0 end
  end
  f = f + 1
  if f >= END then
    local o = io.open("pccount.log", "w")
    for _, n in ipairs(names) do
      local ks = {}
      for k in pairs(hist[n]) do ks[#ks + 1] = k end
      table.sort(ks)
      local s = n .. ":"
      for _, k in ipairs(ks) do s = s .. string.format(" %dx%d", k, hist[n][k]) end
      o:write(s .. "\n")
    end
    o:close(); M:exit()
  end
end)
