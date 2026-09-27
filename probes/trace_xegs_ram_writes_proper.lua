
-- trace_xegs_ram_writes_proper.lua
-- Based on working kareteka-disasm probes: use targeted taps, keep in global TAPS

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local OUT = os.getenv("TRACE_OUT") or "xegs_ram_writes_proper.csv"
local f = io.open(OUT, "w")
f:write("frame,addr,old,new,pc,bank\n")

local F = 0
local cpu = MACHINE.devices[":maincpu"]

local function get_bank()
    return mem:read_u8(0xD500)
end

-- GLOBAL TAPS table - critical for preventing GC
TAPS = {}

-- Watch bank select
TAPS[#TAPS+1] = mem:install_write_tap(0xD500, 0xD500, "bank_select",
    function(offset, data)
        local pc = cpu.state["PC"].value
        f:write(string.format("%d,$%04X,BANK_SELECT,%d,$%04X,-\n", F, offset, data, pc))
        return data
    end)

-- Watch key addresses per page (sample first byte of each 256-byte page)
-- This is much fewer taps than per-byte
local key_pages = {
    { name = "zp", base = 0x0000, pages = 1 },      -- zero page: 1 page
    { name = "stack", base = 0x0100, pages = 1 },   -- stack: 1 page
    { name = "common", base = 0x0480, pages = 1 },  -- common: 128 bytes
    { name = "code", base = 0x1000, pages = 16 },   -- $1000-$1FFF: 16 pages
    { name = "data", base = 0x6000, pages = 32 },   -- $6000-$7FFF: 32 pages
    { name = "sysram", base = 0x1800, pages = 16 }, -- $1800-$27FF: 16 pages
}

for _, p in ipairs(key_pages) do
    for pg = 0, p.pages - 1 do
        local addr = p.base + pg * 0x100
        TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, p.name,
            function(offset, data)
                local old = mem:read_u8(addr)
                local pc = cpu.state["PC"].value
                local bank = get_bank()
                f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
                return data
            end)
    end
end

-- Also watch a few specific known-hot addresses
local hot_addrs = {0x0005, 0x0006, 0x0007, 0x0008}
for _, addr in ipairs(hot_addrs) do
    TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, "hot",
        function(offset, data)
            local old = mem:read_u8(addr)
            local pc = cpu.state["PC"].value
            local bank = get_bank()
            f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
            return data
        end)
end

emu.register_frame_done(function() F = F + 1 end)

local function dump()
    f:flush(); f:close()
    print("trace complete: " .. OUT .. " frames=" .. F .. " taps=" .. #TAPS)
end

if emu.add_machine_stop_notifier then
    STOPPER = emu.add_machine_stop_notifier(dump)
else
    emu.register_stop(dump)
end

print("trace loaded, " .. #TAPS .. " taps (global TAPS retained)")
