-- writes by the framebuffer writers (PCS, hex list: the PCs fbwatch found)
-- that land outside the framebuffer pages ($4010-$72FF): PC, frame, address,
-- value, X and Y (not the stack page: pushes, a JSR or an interrupt, count
-- as the instruction's); to fbstray.log (first 400, then counts), every 1,000 frames and at the end.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local END = tonumber(os.getenv("END") or "20000")
local want = {}
for h in (os.getenv("PCS") or ""):gmatch("%x+") do want[tonumber(h, 16)] = true end
local f, log, n = 0, {}, 0
local function tap(a, d)
  local pc = PCs.value
  if want[pc] and not (a >= 0x4010 and a <= 0x72FF) and not (a >= 0x0100 and a <= 0x01FF) then
    n = n + 1
    if #log < 400 then
      log[#log + 1] = string.format("f%d PC $%04X -> $%04X = $%02X  Y=%02X X=%02X", f, pc, a, d,
        cpu.state["Y"].value, cpu.state["X"].value)
    end
  end
  return d
end
W1 = mem:install_write_tap(0x0000, 0x400F, "s1", tap)
W2 = mem:install_write_tap(0x7300, 0xFFFF, "s2", tap)
local function dump()
  local o = io.open("fbstray.log", "w")
  o:write(string.format("%d stray writes\n", n))
  for _, l in ipairs(log) do o:write(l .. "\n") end
  o:close()
end
emu.register_frame_done(function()
  f = f + 1
  if f % 1000 == 0 then dump() end
  if f >= END then dump(); M:exit() end
end)
