-- at frame AT with playkey.lua driving: the DLI-flagged zones in DLL_A and
-- DLL_B (line numbers), S_VBI_A/B and S_NMIVBI; to dllcheck.log
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
dofile(os.getenv("PROBES") .. "/p7800-sym.lua")
local S = SYM_ADDR
local AT = tonumber(os.getenv("AT") or "3200")
local fr = 0
emu.register_frame_done(function()
  fr = fr + 1
  if fr == AT then
    local o = io.open("dllcheck.log", "w")
    for _, d in ipairs({{"A", 0x2200}, {"B", 0x24E0}}) do
      local flags = {}
      local content_end = nil
      for z = 0, 242 do
        local e = d[2] + 3 * z
        if mem:read_u8(e) & 0x80 ~= 0 then flags[#flags + 1] = tostring(z) end
      end
      o:write(string.format("DLL_%s: DLI zones %s\n", d[1], table.concat(flags, " ")))
    end
    o:write(string.format("S_VBI_A %d S_VBI_B %d S_NMIVBI %d S_PVBI %d\n", mem:read_u8(S.S_VBI_A),
      mem:read_u8(S.S_VBI_B), mem:read_u8(S.S_NMIVBI), mem:read_u8(S.S_PVBI)))
    o:close(); M:exit()
  end
end)
dofile(os.getenv("PROBES") .. "/playkey.lua")
