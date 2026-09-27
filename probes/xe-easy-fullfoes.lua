-- xe-easy-fullfoes.lua -- xe-easy.lua without change 4 (every foe has 1 health), so a
-- fight lasts and both sides land blows; for measuring fights. From xe-easy.lua:
-- Karateka XEGS (MAME `xegs`): a playthrough aid for measuring the
-- original. Five changes, each aimed at one instruction; see FINDINGS.md,
-- "Health, instant deaths and the gate".
--
--   1. Hits cost the player nothing. The damage routine's DEC $B6 at $0BE5
--      keeps the old value. Every other writer of $B6 is left alone: the
--      per-opponent setting ($7BB8, $77AF, $7927) and the refill ($0C28,
--      which counts up until $B6 equals the maximum in $B0).
--   2. No instant death. Hits on the player in the unprotected states
--      (running, walking: $20 = 6-8, $0B-$0D, $22+) reach $B12A, where
--      BEQ $B131 kills outright. The BEQ is fetched as BIT $01, so it falls
--      through to the RTS at $B130 instead.
--   3. The gate in scene 2 never crushes. The check at $79C5 (LDA $A7 /
--      CMP #$82: is the gate low enough) reads $A7 as $00 there.
--   5. No falling off the cliff. Being driven back over the edge sets $A2,
--      and the scene's main loop then marks the player dead (LDA $A2 at
--      $7914 in scenes 1 and 6, the same code at $758D in scene 5's bank);
--      those two reads see $00. Scene 0's attract fight is left alone.
--   4. Every foe has 1 health. Writes to $B7 (the enemy's health) above 1
--      are stored as 1, so one hit through $0BEE finishes any opponent.
--      Not in scene 0: the title and story use $B7 for something else, and
--      clamping it there stops the attract sequence from ever starting a
--      game (measured: 40,000 frames stuck on the title).
--
-- Changes 2-5 need nothing from the player; change 1 only matters when a
-- hit lands. A recording made with this script only replays with it:
-- the batch files name them *-easy.inp and load it again.
--
-- (xe-invincible.lua was version 1: it blocked every lowering of $B6, which
-- also blocked the per-opponent setting, so the refill ran health up to 255
-- and hung at the gate. It is kept only to replay xe-01-inv.inp.)

local M = (type(manager.machine) == "function") and manager:machine() or manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local PC = cpu.state["PC"]

-- globals: a tap held only in a local is garbage-collected
XE_EASY = {
  mem:install_write_tap(0x00B6, 0x00B6, "easy-hits", function(a, d)
    if PC.value == 0x0BE5 then return mem:read_u8(0x00B6) end
    return d
  end),
  mem:install_read_tap(0xB12E, 0xB12E, "easy-instant", function(a, d)
    if PC.value == 0xB12E then return 0x24 end
    return d
  end),
  mem:install_read_tap(0x00A7, 0x00A7, "easy-gate", function(a, d)
    if PC.value == 0x79C5 and mem:read_u8(0x00D0) == 2 then return 0x00 end
    return d
  end),
  mem:install_read_tap(0x00A2, 0x00A2, "easy-cliff", function(a, d)
    local pc = PC.value
    if pc == 0x7914 or pc == 0x758D then
      local s = mem:read_u8(0x00D0)
      if (pc == 0x7914 and (s == 1 or s == 6)) or (pc == 0x758D and s == 5) then return 0x00 end
    end
    return d
  end),
  -- (no one-hit foes in this variant: xe-easy-fullfoes.lua)
}
