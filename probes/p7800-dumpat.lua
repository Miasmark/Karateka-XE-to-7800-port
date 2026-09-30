-- bytes ADDR (hex) .. +LEN at frame AT; to dumpat.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local AT, A, N = tonumber(os.getenv("AT") or "300"), tonumber(os.getenv("ADDR") or "4010", 16), tonumber(os.getenv("LEN") or "128")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if f == AT then
    local o = io.open("dumpat.log", "w")
    for i = 0, N - 1, 16 do
      local t = {}
      for j = 0, 15 do t[#t + 1] = string.format("%02X", mem:read_u8(A + i + j)) end
      o:write(string.format("%04X %s\n", A + i, table.concat(t, " ")))
    end
    o:close(); M:exit()
  end
end)
