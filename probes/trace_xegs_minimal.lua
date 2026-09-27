
-- trace_xegs_minimal.lua
-- Minimal trace using only bank select and periodic RAM sampling

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local OUT = os.getenv("TRACE_OUT") or "xegs_minimal.csv"
local f = io.open(OUT, "w")
f:write("frame,addr,old,new,pc,bank\n")

local F = 0
emu.register_frame_done(function() F = F + 1 end)
local cpu = MACHINE.devices[":maincpu"]

local function get_bank()
    return mem:read_u8(0xD500)
end

local TAPS = {}

-- Only watch bank select and a few critical addresses
-- Bank select register
TAPS[#TAPS+1] = mem:install_write_tap(0xD500, 0xD500, "bank_select",
    function(offset, data)
        local pc = cpu.state["PC"].value
        f:write(string.format("%d,$%04X,BANK_SELECT,%d,$%04X,-\n", F, offset, data, pc))
        return data
    end)

-- Watch only a few specific addresses that are known to be important
-- From the previous trace: $0005, $0006 (zero page), stack, $1000 area
local key_addrs = {0x0005, 0x0006, 0x0007, 0x0008, 0x0100, 0x01FF, 0x0480, 0x04FF, 0x1000, 0x1800}
for _, addr in ipairs(key_addrs) do
    TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, "key",
        function(offset, data)
            local old = mem:read_u8(addr)
            local pc = cpu.state["PC"].value
            local bank = get_bank()
            f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
            return data
        end)
end

local function dump()
    f:flush(); f:close()
    print("trace complete: " .. OUT .. " frames=" .. F)
end

if emu.add_machine_stop_notifier then
    STOPPER = emu.add_machine_stop_notifier(dump)
else
    emu.register_stop(dump)
end

print("minimal trace loaded, " .. #TAPS .. " taps")
