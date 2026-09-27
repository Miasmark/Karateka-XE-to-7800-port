-- boottrace.lua -- log instruction flow from RESET using cpu.debug bpset hooks
local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]
local cpu = MACHINE.devices[":maincpu"]

local OUT = os.getenv("A7800_BT_OUT") or "/tmp/bootflow.txt"
local f = io.open(OUT, "w")
f:write("boot flow trace\n")

local F = 0
emu.register_frame_done(function() F = F + 1 end)

-- hook every instruction via bpset on the reset target; but bpset is per-address.
-- Instead, use the debugger callback on key branch/landing addresses.
-- Since we can't hook "every instruction" cheaply, hook strategic addrs:
--   $CC00 (our RESET stub entry), the stub's targets, and $284E landings.

local function hook(addr, label)
  if not (cpu.debug and cpu.debug.bpset) then
    f:write(string.format("NO DEBUGGER for %s\n", label)); f:flush()
    return
  end
  local ok, err = pcall(function()
    cpu.debug:bpset(addr, nil, function()
      local pc = cpu.debug:pc()
      f:write(string.format("F%-4d EXEC %s $%04X\n", F, label, pc)); f:flush()
    end)
  end)
  f:write(string.format("hook %s ok=%s %s\n", label, tostring(ok), tostring(err)))
  f:flush()
end

hook(0xCC00, "STUB-ENTRY")
hook(0x284E, "TARGET-284E")
hook(0x2CCD, "JSR-2CCD")
hook(0xBECF, "BECF")
hook(0xB929, "B929")
hook(0xBFCF, "BFCF")
hook(0xBE75, "BE75")
hook(0xBE90, "BE90")

local function dump()
  f:flush(); f:close()
end
if emu.add_machine_stop_notifier then emu.add_machine_stop_notifier(dump) end