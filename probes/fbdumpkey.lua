-- both framebuffers at the Nth fetch of KEYPC (an XEGS address in the common
-- bank, default $0862, the game's buffer flip and frame wait; on the 7800 at
-- +$9000), for each N in KEYN ("100,200"), to fbk<N>.bin (A then B); keyed on
-- the game's own progress, so the machines' different speeds don't matter.
-- MACHINE=xe for the original.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local xe = os.getenv("MACHINE") == "xe"
local K = tonumber(os.getenv("KEYPC") or "0862", 16)
if not xe then K = K + 0x9000 end
local A, B = xe and 0x4808 or 0x5808, xe and 0x3010 or 0x4010
local want, last = {}, 0
for n in (os.getenv("KEYN") or "100"):gmatch("%d+") do want[tonumber(n)] = true; last = math.max(last, tonumber(n)) end
local n = 0
T = mem:install_read_tap(K, K, "key", function(a, d)
  if a ~= PCs.value then return d end
  n = n + 1
  if want[n] then
    local o = io.open(string.format("fbk%d.bin", n), "wb")
    for _, base in ipairs({A, B}) do
      local t = {}
      for i = 0, 0x17E7 do t[#t + 1] = string.char(mem:read_u8(base + i)) end
      o:write(table.concat(t))
    end
    o:close()
    if n >= last then M:exit() end
  end
  return d end)
