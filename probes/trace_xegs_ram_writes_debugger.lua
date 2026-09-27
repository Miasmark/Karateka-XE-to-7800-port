
-- trace_xegs_ram_writes_debugger.lua
-- Use MAME debugger watchpoints instead of per-byte taps (faster, no crash)

-- This script registers debugger watchpoints for RAM ranges
-- Then we can use MAME's debugger to log writes

local MACHINE = (type(manager.machine) == "function") and manager:machine() or manager.machine

-- Use the debugger to set watchpoints
local dbg = MACHINE.debugger
if not dbg then
    print("Debugger not available")
    return
end

-- Frame counter
local F = 0
emu.register_frame_done(function() F = F + 1 end)

-- Set up watchpoints via debugger commands
-- Watch the key RAM ranges the game uses
local cmds = {
    "wp 1000,1fff,w",  -- code bank
    "wp 6000,7fff,w",  -- data bank  
    "wp 0480,04ff,w",  -- common area
    "wp 1800,27ff,w",  -- system RAM
}

for _, cmd in ipairs(cmds) do
    dbg:command(cmd)
end

-- Hook to log when watchpoints trigger
-- We need to use the debugger's callback mechanism
-- Actually, let's use a different approach: log via Lua on each frame
-- but only sample specific addresses

print("Watchpoints set for key RAM ranges")
print("Use MAME debugger 'log' command to trace writes")
