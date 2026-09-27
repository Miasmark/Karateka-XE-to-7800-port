#!/usr/bin/env python3
"""
The relocation list: every byte of XEGS Karateka that is the high half of an
address, and the region it points into.

Every move in the 7800 layout is a whole number of pages, so an address's
low byte never changes; relocating means adding the region's page delta to
its high bytes. That needs only where the high bytes are and which region
each points into.

Sources:
  - the origin trace's direct origins (the stored byte *is* the pointer's
    high byte), from work/analysis/origin/origin*.txt
  - the cases found by reading the code (MANUAL below): framebuffer constants
    that are only compared, and the small-sprite block's base

    python port/reloclist.py > work/analysis/reloc.txt

Output lines:  scene|*  location  imm|byte  value  region  target
  scene   the scene whose banks hold the byte, or * for shared segments
  imm     an immediate operand (the location is the operand byte)
  target  the lowest address a pointer built with this byte reached
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dis as D  # noqa: E402  (only main() needs it)

REGIONS = [   # XEGS address ranges that move as one piece
    ("zp", 0x0000, 0x0100), ("stack", 0x0100, 0x0200), ("os_ram", 0x0200, 0x0480),
    ("sprites", 0x0480, 0x06E8), ("common", 0x06E8, 0x1000),
    ("engine1", 0x1000, 0x1203), ("scode", 0x1203, 0x2300),
    ("engine2", 0x2300, 0x24A5), ("scode2", 0x24A5, 0x24AC), ("engine3", 0x24AC, 0x3000),
    ("fbB", 0x3000, 0x4800), ("fbA", 0x4800, 0x6000), ("sdata", 0x6000, 0x8000),
    ("art", 0x8000, 0xA000), ("bank15", 0xA000, 0xC000), ("os", 0xC000, 0x10000),
]
SCENE_SPECIFIC = ("scode", "scode2", "sdata")

# read from the code (FINDINGS, "Reviewing the derived origins"): operand
# locations of immediates that are high bytes of framebuffer or sprite-block
# addresses but are compared or added, not used as pointers directly
MANUAL = [
    # framebuffer clear $280F: base (self-modified store) and end
    ("*", 0x2818, "fbB"), ("*", 0x2821, "fbB"), ("*", 0x2829, "fbA"), ("*", 0x2832, "fbA"),
    # row address: ADC #$30 / ADC #$48 into $15
    ("*", 0x2D66, "fbB"), ("*", 0x2D74, "fbA"),
    # bank 15 buffer setup $AD8E-$ADC6: bases and ends
    ("*", 0xAD97, "fbB"), ("*", 0xAD9F, "fbA"), ("*", 0xADAA, "fbB"),
    ("*", 0xADB3, "fbA"), ("*", 0xADBB, "fbB"), ("*", 0xADC6, "fbA"),
    # small-sprite block: pointer = table offset + $0480 ($0796-$07A3)
    ("*", 0x07A2, "sprites"),
    # interrupt vectors installed through the OS (which jumps through them from
    # its own ROM, where the origin trace does not look): SETVBV's X at $0E90
    # (vertical blank $0F18) and VDSLST's high byte at $0E9C (DLI $1026)
    ("*", 0x0E91, "common"),
    ("*", 0x0E9D, "engine1"),
    # blit-source high bytes (LDA #imm / STA $04) on paths no census run took
    # (a scan of every scene for them, FINDINGS "Scene 1"): scene 1's death
    # sprites at $1Exx, and two scene 4 pointers into its scene data
    ("1", 0x6C58, "scode"),
    ("4", 0x703C, "sdata"), ("4", 0x7CD5, "sdata"),
    # scene 0 past the cutscene (the opening run the attract sequence plays),
    # which no census run reached (probes/scanhi.py; FINDINGS "Story crash"):
    # blit sources $7E60 ($78D4) and $7FA9 ($7933), and the text pointers of
    # the stubs at $620E/$622C (called only from the block after $7790's JMP)
    ("0", 0x78D5, "sdata"), ("0", 0x7934, "sdata"),
    ("0", 0x6217, "sdata"), ("0", 0x6226, "sdata"), ("0", 0x6235, "sdata"), ("0", 0x6244, "sdata"),
]
# pointer tables (split low/high), relocated whole: the census relocated only
# the entries its runs used, and the rest crash when the game reaches them
# (scene, low table, high table, entries, region[, stride: 2 for interleaved])
MANUAL_TABLES = [
    # the story text lines ($7983: LDA $7BCC,X / LDA $7BE6,X into $E5/$E6):
    # the census pressed fire at frame 1800 and skipped lines 18-25, so
    # "Defeat Akuma and rescue the..." onward read cartridge RAM as text
    # and the renderer went off the rails (FINDINGS "Story crash")
    ("0", 0x7BCC, 0x7BE6, 26, "sdata"),
    # the opening run's scenery sprites ($6383: LDA $6347,X / LDA $6353,X,
    # X 12-23 from $773C), after the cutscene
    ("0", 0x6353, 0x635F, 12, "sdata"),
    # scene 4's finale, the fighters' and Mariko's frames (region per entry:
    # "auto"): the census playthrough freed Mariko the one way, and the
    # other frames' high bytes stayed unrelocated; the user's recording
    # reached one ($16AE, index 24 of $1D0F/$1D34) and the blitter drew
    # console RAM as a sprite with width 0, 256 bytes a row, into the engine
    # (FINDINGS "The princess room")
    ("4", 0x7DD9, 0x7DDF, 6, "auto"), ("4", 0x7E00, 0x7E22, 34, "auto"),
    ("4", 0x7E88, 0x7EA3, 27, "auto"), ("4", 0x7EF4, 0x7F0F, 27, "auto"),
    ("4", 0x7F60, 0x7F82, 34, "auto"), ("4", 0x1D0F, 0x1D34, 37, "auto"),
    # the sound driver's tune table ($2422: tune number x 2 into $25C0,
    # interleaved low, high; 28 tunes, the 29th entry is tune 0's first list
    # word, also a pointer): the census heard tunes 0, 12 and 17-28, and the
    # others' high bytes stayed XEGS engine addresses ($25xx/$26xx), which on
    # the 7800 are console RAM in the middle of DLL_B. The pointers below the
    # table are music_pointers' (FINDINGS "The silent Akuma fight")
    ("*", 0x25C0, 0x25C1, 29, "auto", 2),
]
MUSIC = (0x1203, 0x3000)      # scene code and engine2: where tune data lives


def music_stream(mem, q):
    """A note stream at q parses: its header pointer, then notes (length,
    voice 1, voice 2: $2300 table offsets, 0 = rest, $FF = hold) and $FE
    pattern changes, to $FF."""
    h = mem.get(q, 0) | mem.get(q + 1, 0) << 8
    if not MUSIC[0] <= h < MUSIC[1]:
        return False
    j = q + 2
    for _ in range(400):
        c = mem.get(j)
        if c is None:
            return False
        if c == 0xFF:
            return True
        if c == 0xFE:
            j += 2
            continue
        if any(v not in (0, 0xFF) and v & 1 for v in (mem.get(j + 1), mem.get(j + 2))):
            return False
        j += 3
    return False


def music_pointers(mem):
    """Every pointer in the tune data of one scene's memory, {location:
    target}: the tune table ($25C0) -> tune lists (words: a pattern
    reference, or $FF end, or 4-byte $FE/$FD commands, $2441) -> a pattern
    reference (a word: the stream, $2451) -> the stream, whose first word
    points at its header (tempo and voice settings, $259D). A reference
    whose stream does not parse is not this scene's music (the scene-code
    words at $2000 differ by scene) and is left alone."""
    w = lambda a: mem[a] | mem[a + 1] << 8
    out = {}
    for i in range(28):
        t = out[0x25C0 + 2 * i] = w(0x25C0 + 2 * i)
        k = 0
        while mem[t + k + 1] != 0xFF:
            if mem[t + k + 1] in (0xFE, 0xFD):
                k += 4
                continue
            p = w(t + k)
            q = w(p) if MUSIC[0] <= p < MUSIC[1] else None
            if q is not None and MUSIC[0] <= q < MUSIC[1] and music_stream(mem, q):
                out[t + k], out[p], out[q] = p, q, w(q)
            k += 2
    return out
IMM = {0xA9, 0xA2, 0xA0, 0xC9, 0xE0, 0xC0, 0x69, 0xE9, 0x09, 0x29, 0x49}


SHARED_RUN = 16


def shared_with_twin(mems, scene, loc, twin=1):
    """Scene `scene` holds scene `twin`'s bytes around loc (SHARED_RUN either
    side), JSR/JMP operands aside: scene 0's copy calls the engine at other
    entries ($284E where scene 1 has $2803, $2B82 for $2809)."""
    m0, m1 = mems[scene], mems[twin]

    def same(a):
        if m0.get(a) is None:
            return False
        if m0.get(a) == m1.get(a):
            return True
        return any(m0.get(a - k) == m1.get(a - k) and m0.get(a - k) in (0x20, 0x4C)
                   for k in (1, 2))
    return all(same(a) for a in range(loc - SHARED_RUN, loc + SHARED_RUN + 1))


def region(a):
    for name, lo, hi in REGIONS:
        if lo <= a < hi:
            return name
    return "?"


def main():
    root = os.path.join(HERE, "..", "work", "analysis")
    ex = {}
    for p in glob.glob(os.path.join(root, "census", "*.ex")):
        for line in open(p):
            k = int(line.split()[0])
            ex.setdefault((k >> 16) & 0xFF, set()).add(k & 0xFFFF)
    mems = {s: D.memory(s) for s in (0, 1, 2, 3, 4, 6)}

    out = {}
    for p in glob.glob(os.path.join(root, "origin", "origin*.txt")):
        for line in open(p):
            kind, pc, hi, lo, n, tlo, thi = line.split()
            hi, tlo = int(hi), int(tlo, 16)
            if hi < 0:
                continue
            scene, loc = (hi >> 16, hi & 0xFFFF) if hi >= 0x10000 else (None, hi)
            if scene is None and region(loc) in SCENE_SPECIFIC:
                scene = 0                      # scene*65536+addr is just addr for scene 0
            if region(loc) in ("zp", "stack", "os_ram", "fbA", "fbB", "os"):
                continue                       # built in RAM, not a stored byte
            m = mems[scene if scene is not None else 1]
            v = m.get(loc)
            if v is None or not (tlo >> 8) <= v <= ((tlo >> 8) + 1):
                continue                       # derived: read by hand (MANUAL)
            tgt = region(tlo) if region(tlo) == region(v << 8) else region(v << 8)
            is_imm = m.get(loc - 1) in IMM and (loc - 1) in ex.get(scene if scene is not None else 1, set())
            shared = region(loc) not in SCENE_SPECIFIC
            key = ("*" if shared else str(scene), loc)
            prev = out.get(key)
            t = tlo if prev is None else min(prev[3], tlo)
            out[key] = ("imm" if is_imm else "byte", v, tgt, t)
    for scene, loc, tgt in MANUAL:
        v = mems[1 if scene == "*" else int(scene)].get(loc)
        out[(scene, loc)] = ("imm", v, tgt, v * 256 + (0x10 if tgt in ("fbA", "fbB") else 0x80))
    for entry in MANUAL_TABLES:
        scene, lo, hi, n, tgt = entry[:5]
        step = entry[5] if len(entry) > 5 else 1     # 2: interleaved low, high
        mem = mems[1 if scene == "*" else int(scene)]
        for i in range(n):
            v = mem.get(hi + i * step)
            reg = region(v << 8) if tgt == "auto" else tgt
            if reg in ("art", "bank15", "os", "?"):
                continue                       # does not move (or is not a pointer)
            out[(scene, hi + i * step)] = ("byte", v, reg, v * 256 + mem.get(lo + i * step))
    # the music's pointers: the census relocated those its runs played;
    # the Akuma fight's tune (13-16: $261E -> $2000 -> $200A in scene 4)
    # was not among them, and on the 7800 the sequencer read notes from
    # console RAM (FINDINGS "The silent Akuma fight")
    for s in (0, 1, 2, 3, 4, 6):
        for loc, t in music_pointers(mems[s]).items():
            scene = str(s) if region(loc) in SCENE_SPECIFIC else "*"
            key = (scene, loc + 1)
            if key not in out:
                out[key] = ("byte", t >> 8, region(t), t)
    # scenes 0 and 6 carry copies of scene 1's code and data at the same addresses
    # (the opening run that the attract sequence plays after the cutscene);
    # no census run reached it there, so scene 1's entries are applied to it
    # wherever the two scenes' bytes agree for SHARED_RUN bytes around the
    # location (FINDINGS "Story crash")
    # and scene 6 (Select at the title: the fight at the gate) is scene 1 with
    # 231 bytes changed; it writes $D0 = 1 and plays on in its own banks, so
    # the census filed its fight under scene 1 (FINDINGS "Select, scene 6")
    for (scene, loc), entry in list(out.items()):
        if scene != "1":
            continue
        for twin in ("0", "6"):
            if (twin, loc) not in out and shared_with_twin(mems, int(twin), loc):
                out[(twin, loc)] = entry
    print("# generated by port/reloclist.py: scene|* location imm|byte value region target")
    for (scene, loc), (kind, v, tgt, t) in sorted(out.items(), key=lambda x: (x[0][1], x[0][0])):
        print("%s %04X %s %02X %s %04X" % (scene, loc, kind, v, tgt, t))


if __name__ == "__main__":
    main()
