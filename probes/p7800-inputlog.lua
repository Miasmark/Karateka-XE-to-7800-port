-- carry a recording across cartridges: MODE=log (the cartridge the
-- recording was made on, with -playback) saves the machine state at frame
-- SAVEAT (as STATE, default "handoff") and from there logs, per frame, every
-- value the game reads from SWCHA $0280, SWCHB $0282 and INPT4/INPT5 $000C/
-- $000D, to inputs.log; MODE=feed (another cartridge) loads that state at
-- its second frame (-state on the command line never ran a frame here) and
-- answers those reads from inputs.log (INPUTS: its path) frame by frame,
-- counted from the load. Pass -state_directory for both. Frames are matched by order, as the
-- state resumes at the same point.
local M = manager.machine
local mem = M.devices[":maincpu"].spaces["program"]
local MODE = os.getenv("MODE") or "log"
local SAVEAT = tonumber(os.getenv("SAVEAT") or "0")
local END = tonumber(os.getenv("END") or "0")
local f = 0
local regs = {[0x0280] = "A", [0x0282] = "B", [0x000C] = "4", [0x000D] = "5"}
if MODE == "log" then
  local o = io.open("inputs.log", "w")
  local cur = {}
  local function tap(a, d)
    if f >= SAVEAT then cur[regs[a]] = d end
    return d end
  T1 = mem:install_read_tap(0x0280, 0x0280, "swcha", tap)
  T2 = mem:install_read_tap(0x0282, 0x0282, "swchb", tap)
  T3 = mem:install_read_tap(0x000C, 0x000D, "inpt", tap)
  emu.register_frame_done(function()
    f = f + 1
    if f == SAVEAT then M:save(os.getenv("STATE") or "handoff") end
    if f > SAVEAT then
      o:write(string.format("%s %s %s %s\n", cur.A or "-", cur.B or "-", cur["4"] or "-", cur["5"] or "-"))
      cur = {}
    end
    if END > 0 and f >= END then o:close(); M:exit() end
  end)
else
  local frames = {}
  for line in io.lines(os.getenv("INPUTS")) do
    local a, b, i4, i5 = line:match("(%S+) (%S+) (%S+) (%S+)")
    frames[#frames + 1] = {A = tonumber(a), B = tonumber(b), ["4"] = tonumber(i4), ["5"] = tonumber(i5)}
  end
  local last = {}
  local loaded = false
  local function tap(a, d)
    if not loaded then return d end
    local fr = frames[f + 1]
    local v = fr and fr[regs[a]]
    if v then last[regs[a]] = v end
    return v or last[regs[a]] or d end
  T1 = mem:install_read_tap(0x0280, 0x0280, "swcha", tap)
  T2 = mem:install_read_tap(0x0282, 0x0282, "swchb", tap)
  T3 = mem:install_read_tap(0x000C, 0x000D, "inpt", tap)
  local boot = 0
  emu.register_frame_done(function()
    if not loaded then
      boot = boot + 1
      if boot == 2 then
        M:load(os.getenv("STATE") or "handoff"); loaded = true
        -- PATCH="addr:hexbytes,...": RAM the state carries from the old
        -- build that the new one changes (the engine is loaded to cartridge
        -- RAM at power-on, so a state brings the old copy)
        for spec in (os.getenv("PATCH") or ""):gmatch("[^,]+") do
          local a, hex = spec:match("(%x+):(%x+)")
          a = tonumber(a, 16)
          for i = 1, #hex, 2 do mem:write_u8(a + (i - 1) // 2, tonumber(hex:sub(i, i + 1), 16)) end
        end
      end
      return
    end
    f = f + 1
    if END > 0 and f >= END then M:exit() end
  end)
end
