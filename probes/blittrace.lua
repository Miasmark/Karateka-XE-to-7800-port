-- instruction trace of blit number BLIT (0-based, counted at $29E0 as in
-- blitlog.lua) until TRACEN instructions: PC in XEGS terms (the 7800 engine
-- at $7000-$7FFF shown at $1000-$1FFF/$2300-$2FFF), A X Y, only engine PCs
-- (interrupts left out: from the NMI entry until the stack is back where it
-- was). To trace.log.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PCs, As, Xs, Ys, Ps = cpu.state["PC"], cpu.state["A"], cpu.state["X"], cpu.state["Y"], cpu.state["P"]
local xe = os.getenv("MACHINE") == "xe"
local START = xe and 0x29E0 or 0x79E0
local BLIT = tonumber(os.getenv("BLIT") or "4")
local Z14 = xe and 0x14 or tonumber(os.getenv("ZP14") or "D5", 16)   -- the destination pointer
local Z3 = xe and 0x03 or tonumber(os.getenv("ZP3") or "C9", 16)       -- the source pointer
local FB = xe and 0 or 0x1000                                       -- shown in XEGS terms
local TRACEN = tonumber(os.getenv("TRACEN") or "20000")
local n, on, count = 0, false, 0
local SPs = cpu.state["SP"]
local NMI = -1              -- read at the first blit, once the cartridge is in
local irq_sp = nil
local o = io.open("trace.log", "w")
T = mem:install_read_tap(0x0000, 0xFFFF, "tr", function(a, d)
  if a ~= PCs.value then return d end
  if a == START then
    NMI = mem:read_u8(0xFFFA) | (mem:read_u8(0xFFFB) << 8)
    if n == BLIT then on = true end
    n = n + 1
  end
  local sp = SPs.value & 0xFF
  if irq_sp and sp >= irq_sp then irq_sp = nil end
  if a == NMI and not irq_sp then irq_sp = sp + 3 end
  if on and not irq_sp then
    local x = a
    if not xe then
      if a >= 0x7000 and a < 0x7203 then x = a - 0x6000
      elseif a >= 0x7300 and a < 0x8000 then x = a - 0x5000 else x = nil end
    elseif a >= 0x3000 or a < 0x1000 then x = nil end
    if x then
      local dst = (mem:read_u8(Z14) | (mem:read_u8(Z14 + 1) << 8)) - FB
      local src = mem:read_u8(Z3) | (mem:read_u8(Z3 + 1) << 8)
      o:write(string.format("%04X %02X A%02X X%02X Y%02X C%d D%04X S%04X\n", x, d, As.value, Xs.value, Ys.value,
        Ps.value & 1, dst, src))
      count = count + 1
      if count >= TRACEN then on = false; o:close(); M:exit() end
    end
  end
  return d end)
emu.register_frame_done(function() end)
