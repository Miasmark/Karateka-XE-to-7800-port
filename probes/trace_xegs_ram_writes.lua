
-- trace_xegs_ram_writes.lua
-- Trace ALL writes to XEGS RAM ranges during Karateka playthrough
-- Usage: mame xegs -cart Karateka.car -autoboot_script trace_xegs_ram_writes.lua -video none -sound none -nothrottle -str 180

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

-- Output file
local OUT = os.getenv("TRACE_OUT") or "xegs_ram_writes.log"
local f = io.open(OUT, "w")
f:write("frame,addr,old,new,pc,bank\n")

-- Frame counter
local F = 0
emu.register_frame_done(function() F = F + 1 end)

-- CPU for PC register
local cpu = MACHINE.devices[":maincpu"]

-- XEGS cartridge bank register ($D500)
local function get_current_bank()
    return mem:read_u8(0xD500)
end

-- Watch ranges: the game uses $1000-$9FFF for code/data, $0480-$04FF for common
-- On XEGS, system RAM is at $1800-$27FF + mirrors, plus expansion
local WATCH_RANGES = {
    { name = "code_bank_1000", lo = 0x1000, hi = 0x1FFF },  -- 4K code bank
    { name = "data_bank_6000", lo = 0x6000, hi = 0x7FFF },  -- 8K data bank  
    { name = "common_0480",    lo = 0x0480, hi = 0x04FF },  -- 128B common
    { name = "zero_page",      lo = 0x0000, hi = 0x00FF },  -- zero page
    { name = "stack_page",     lo = 0x0100, hi = 0x01FF },  -- stack
    { name = "system_ram_1800", lo = 0x1800, hi = 0x27FF }, -- onboard RAM
}

-- Keep tap references alive
local TAPS = {}

for _, range in ipairs(WATCH_RANGES) do
    for addr = range.lo, range.hi do
        TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, range.name,
            function(offset, data)
                if F >= 0 then  -- log all frames
                    local old = mem:read_u8(addr)
                    local pc = cpu.state["PC"].value
                    local bank = get_current_bank()
                    f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
                end
                return data
            end)
    end
end

-- Also watch bank select register
TAPS[#TAPS+1] = mem:install_write_tap(0xD500, 0xD500, "bank_select",
    function(offset, data)
        local pc = cpu.state["PC"].value
        f:write(string.format("%d,$%04X,BANK_SELECT,%d,$%04X,-\n", F, offset, data, pc))
        return data
    end)

local function dump()
    f:flush(); f:close()
    print("trace complete: wrote " .. OUT .. " frames=" .. F)
end

if emu.add_machine_stop_notifier then
    STOPPER = emu.add_machine_stop_notifier(dump)
else
    emu.register_stop(dump)
end

print("trace_xegs_ram_writes.lua loaded, watching " .. #WATCH_RANGES .. " ranges")
