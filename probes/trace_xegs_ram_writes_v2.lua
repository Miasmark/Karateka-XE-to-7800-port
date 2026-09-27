
-- trace_xegs_ram_writes_v2.lua
-- Trace writes to key RAM ranges using fewer taps (sample key addresses per page)

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local OUT = os.getenv("TRACE_OUT") or "xegs_ram_writes_v2.csv"
local f = io.open(OUT, "w")
f:write("frame,addr,old,new,pc,bank\n")

local F = 0
emu.register_frame_done(function() F = F + 1 end)
local cpu = MACHINE.devices[":maincpu"]

local function get_bank()
    return mem:read_u8(0xD500)
end

local TAPS = {}

-- Watch only key addresses per page (first byte of each 256-byte page)
-- This gives us page-level write activity without crashing
local WATCH_PAGES = {
    -- Zero page: every byte (small)
    { name = "zp", lo = 0x0000, hi = 0x00FF, step = 1 },
    -- Stack: every byte
    { name = "stack", lo = 0x0100, hi = 0x01FF, step = 1 },
    -- Common: every byte
    { name = "common", lo = 0x0480, hi = 0x04FF, step = 1 },
    -- Code bank $1000-$1FFF: sample every page (16 pages)
    { name = "code", lo = 0x1000, hi = 0x1FFF, step = 0x100 },
    -- Data bank $6000-$7FFF: sample every page (32 pages)
    { name = "data", lo = 0x6000, hi = 0x7FFF, step = 0x100 },
    -- System RAM $1800-$27FF: sample every page (16 pages)
    { name = "sysram", lo = 0x1800, hi = 0x27FF, step = 0x100 },
}

for _, r in ipairs(WATCH_PAGES) do
    for addr = r.lo, r.hi, r.step do
        TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, r.name,
            function(offset, data)
                if F >= 0 then
                    local old = mem:read_u8(addr)
                    local pc = cpu.state["PC"].value
                    local bank = get_bank()
                    f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
                end
                return data
            end)
    end
end

-- Bank select
TAPS[#TAPS+1] = mem:install_write_tap(0xD500, 0xD500, "bank_select",
    function(offset, data)
        local pc = cpu.state["PC"].value
        f:write(string.format("%d,$%04X,BANK_SELECT,%d,$%04X,-\n", F, offset, data, pc))
        return data
    end)

local function dump()
    f:flush(); f:close()
    print("trace complete: " .. OUT .. " frames=" .. F)
end

if emu.add_machine_stop_notifier then
    STOPPER = emu.add_machine_stop_notifier(dump)
else
    emu.register_stop(dump)
end

print("trace v2 loaded, watching " .. #TAPS .. " taps")
