-- the last write to every framebuffer byte ($4010-$72FF): PC, frame and the
-- picture count (buffer flips, $2C changes); at the end of each frame in AT
-- (comma list), to lastwriter-<frame>.txt: "addr value pc frame picture",
-- one line a byte. END frames.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs = cpu.state["PC"]
local END = tonumber(os.getenv("END") or "20000")
local AT = {}
for n in (os.getenv("AT") or ""):gmatch("%d+") do AT[tonumber(n)] = true end
local f, pic, last = 0, 0, nil
local wpc, wf, wp = {}, {}, {}
W1 = mem:install_write_tap(0x4010, 0x72FF, "lw", function(a, d)
  wpc[a] = PCs.value; wf[a] = f; wp[a] = pic; return d end)
W2 = mem:install_write_tap(0x002C, 0x002C, "lp", function(a, d)
  if last and d ~= last then pic = pic + 1 end
  last = d; return d end)
emu.register_frame_done(function()
  f = f + 1
  if AT[f] then
    local o = io.open("lastwriter-" .. f .. ".txt", "w")
    o:write(string.format("# frame %d picture %d $2C=%02X\n", f, pic, mem:read_u8(0x2C)))
    for a = 0x4010, 0x72FF do
      if (a & 0xFF) >= 16 then
        o:write(string.format("%04X %02X %04X %d %d\n", a, mem:read_u8(a), wpc[a] or 0, wf[a] or -1, wp[a] or -1))
      end
    end
    o:close()
  end
  if f >= END then M:exit() end
end)
