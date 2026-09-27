
-- trace_xegs_ram_writes_gameplay_v2.lua
-- Try different button port names and longer auto-fire

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine
local mem = MACHINE.devices[":maincpu"].spaces["program"]

local OUT = os.getenv("TRACE_OUT") or "xegs_ram_writes_gameplay_v2.csv"
local f = io.open(OUT, "w")
f:write("frame,addr,old,new,pc,bank\n")

local F = 0
local cpu = MACHINE.devices[":maincpu"]

local function get_bank()
    return mem:read_u8(0xD500)
end

TAPS = {}

-- Bank select
TAPS[#TAPS+1] = mem:install_write_tap(0xD500, 0xD500, "bank_select",
    function(offset, data)
        local pc = cpu.state["PC"].value
        f:write(string.format("%d,$%04X,BANK_SELECT,%d,$%04X,-\n", F, offset, data, pc))
        return data
    end)

-- Watch key pages (sample per page)
local key_pages = {
    { name = "zp", base = 0x0000, pages = 1 },
    { name = "stack", base = 0x0100, pages = 1 },
    { name = "common", base = 0x0480, pages = 1 },
    { name = "code", base = 0x1000, pages = 16 },
    { name = "data", base = 0x6000, pages = 32 },
    { name = "sysram", base = 0x1800, pages = 16 },
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

-- Hot addresses
for _, addr in ipairs({0x0005, 0x0006, 0x0007, 0x0008}) do
    TAPS[#TAPS+1] = mem:install_write_tap(addr, addr, "hot",
        function(offset, data)
            local old = mem:read_u8(addr)
            local pc = cpu.state["PC"].value
            local bank = get_bank()
            f:write(string.format("%d,$%04X,%d,%d,$%04X,%d\n", F, addr, old, data, pc, bank))
            return data
        end)
end

-- Try multiple possible button port names for XEGS
local fire_field = nil
local port_names = {":buttons", ":joystick", ":joy1", ":joy2", ":p1", ":player1", ":djoy"}
for _, pname in ipairs(port_names) do
    local port = MACHINE.ioport.ports[pname]
    if port then
        -- Try common field names
        for _, fname in ipairs({"P1 Button 1", "P1 Fire", "Fire", "Button 1", "P1 Button 2", "P2 Button 1"}) do
            if port.fields[fname] then
                fire_field = port.fields[fname]
                print("Found fire field: " .. pname .. " -> " .. fname)
                break
            end
        end
        if fire_field then break end
    end
end

-- Also print all available ports for debugging
print("Available ports:")
for name, port in pairs(MACHINE.ioport.ports) do
    print("  " .. name)
    for fname, field in pairs(port.fields) do
        print("    " .. fname)
    end
end

emu.register_frame_done(function()
    F = F + 1
    -- Auto-fire: hold fire from frame 100 to 10000
    if fire_field and F >= 100 and F <= 10000 then
        fire_field:set_value(1)
    elseif fire_field then
        fire_field:set_value(0)
    end
end)

local function dump()
    f:flush(); f:close()
    print("trace complete: " .. OUT .. " frames=" .. F .. " taps=" .. #TAPS)
end

if emu.add_machine_stop_notifier then
    STOPPER = emu.add_machine_stop_notifier(dump)
else
    emu.register_stop(dump)
end

print("gameplay trace v2 loaded, " .. #TAPS .. " taps")
