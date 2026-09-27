#!/usr/bin/env python3
"""
Where every part of XEGS Karateka lives in the 7800 build. See FINDINGS.md,
"The display lists, and the layout that holds", for why.

This module is data plus the address map; port/link7800.py uses it to
assemble each piece of the game at its 7800 address.

The map is by XEGS address and, where scenes differ, by scene:

  sprites  $0480-$06E7  console RAM $1B80   (written: header clipping)
  common   $06E8-$0FFF  scene page  $96E8   (a copy in every scene page)
  engine   $1000-$1202  cart RAM    $7000   (self-modifying; copied at load)
  scode    $1203-$22FF  scene page  $8203
  engine   $2300-$2FFF  cart RAM    $7300   ($24A5-$24AB differ per scene)
  fb B     $3000-$47FF  cart RAM    $4000
  fb A     $4800-$5FFF  cart RAM    $5800
  sdata    $6000-$7FFF  scene page  $A000
  art      $8000-$9FFF  art bank    $8000
  bank 15  $A000-$BFFF  fixed       $C000   (may grow; nothing points into it)

Every move of a region is a whole number of pages, so an address's low byte
never changes. Exceptions, which carry their own mapping:

  - carve-outs: bytes the game writes inside regions that live in ROM (a
    write to $8000-$BFFF switches banks on the 7800); they get RAM homes;
  - scene-code and arrow sprites: page-aligned copies in the fixed bank,
    for the scenes that draw them (the blit's bank is chosen from its
    source page, and these would collide with the art's pages);
  - zero page: XEGS $00-$3F are the 7800's TIA and MARIA registers.
"""

# ---------------------------------------------------------------- regions
REGIONS = [   # name, XEGS start, end (exclusive), 7800 start, where
    ("sprites", 0x0480, 0x06E8, 0x1B80, "ram"),
    ("common", 0x06E8, 0x1000, 0x96E8, "page"),
    ("engine1", 0x1000, 0x1203, 0x7000, "cram"),
    ("scode", 0x1203, 0x2300, 0x8203, "page"),
    ("engine2", 0x2300, 0x3000, 0x7300, "cram"),
    ("fbB", 0x3000, 0x4800, 0x4000, "cram"),
    ("fbA", 0x4800, 0x6000, 0x5800, "cram"),
    ("sdata", 0x6000, 0x8000, 0xA000, "page"),
    ("art", 0x8000, 0xA000, 0x8000, "art"),
    ("bank15", 0xA000, 0xC000, 0xC000, "fixed"),
]

SCENES = (0, 1, 2, 3, 4, 6)
SCENE_BANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 6: 5}      # 7800 bank per scene
ART_BANK = 6
FIXED_BANK = 7

# ------------------------------------------------------------ carve-outs
# bytes the game writes inside ROM-resident regions (census, all runs):
# (XEGS start, end exclusive) -> RAM start; blocks keep their internal layout
CARVE_COMMON = [
    (0x0880, 0x0900, 0x1880),      # the zero-page swap buffer (moved from $1A00
                                   # so page $19 and $1A00-$1A08 hold scene 1's
                                   # death sprites, below)
    (0x0AF6, 0x0AFF, 0x1A80),
    (0x0B26, 0x0B27, 0x1A89),
    (0x0C4C, 0x0C51, 0x1A8A),
    (0x0F09, 0x0F18, 0x1A8F),
]
CARVE_SDATA = {                    # per scene
    # scene 1 also: the player's death sprites in scene code, $1E00 19x4,
    # $1E4E 15x7, $1EB9 12x2, $1ED3 13x4 (drawn by $6C52; no census run died, so
    # it was never traced). Scene code sits at $8203+ in the scene page, the
    # art bank's half of the blit rule, so they are read from a RAM copy the
    # loader makes (FINDINGS, "Scene 1")
    1: [(0x7096, 0x7098, 0x1A9E), (0x1E00, 0x1F09, 0x1900)],
    # scene 0: the same pair, and $6009 (written as the story ends, $740A: in
    # ROM a write there is a bank switch, and the next fetch came from bank 7;
    # the census skipped the story's end; FINDINGS "Story crash"); and
    # scene 1's death sprites, which scene 0's copy of the opening run
    # draws too (the same bytes, $1E00-$1F08)
    0: [(0x7096, 0x7098, 0x1A9E), (0x6009, 0x600A, 0x1AA0), (0x1E00, 0x1F09, 0x1900)],
    4: [(0x76FF, 0x7700, 0x1A9E), (0x7706, 0x7707, 0x1A9F)],
    # scene 6 (Select at the title: the fight at the gate) runs scene 1's
    # code in its own banks, flags at $7096/$7097 included (in ROM a write
    # there is a bank switch), and its death sprites; FINDINGS "Select,
    # scene 6"
    6: [(0x7096, 0x7098, 0x1A9E), (0x1E00, 0x1F09, 0x1900)],
}

# ------------------------------------------- sprites copied to the art bank
# scene-code sprites a scene draws that the fixed bank has no room for: copied
# into the art bank's free space (above its images, $B179-$BFFF), page-aligned,
# and read there because the scene's page map (SP_PAGEMAP, 32 bytes for pages
# $A0-$BF in each scene page) sends the blit to the art bank for those pages;
# the scene must draw nothing of its own from them. (start, end exclusive,
# page delta, scenes)
ART_COPIES = [
    # scene 0's intro cutscene (after the story): Akuma, Mariko, the guard; its
    # data-bank sprites use only pages $A1 and $BC-$BE (FINDINGS "Story crash")
    (0x1530, 0x18D8, 0xA000, (0,)),             # $B530-$B8D7
    (0x1CC4, 0x1DFB, 0x9D00, (0,)),             # $B9C4-$BAFA
    # scene 4's finale: Mariko's frame at $1F29 (43x4), in the gap between
    # its fixed-bank copies at $1F00 and $1FD7, where the TIA tables now sit;
    # page $BB, which scene 4 never draws from in its own data (its sprite
    # pages are $60-$6F, $75, $76; FINDINGS "The princess room")
    (0x1F29, 0x1FD7, 0x9C00, (4,)),             # $BB29-$BBD6
    # scene 4's own $16FE-$18A1 (the finale's frames), which differ from
    # scenes 2 and 3's at the same addresses: the shared fixed-bank copy was
    # scene 2's, so the finale drew scene 2's bytes there; pages $BC-$BE,
    # not drawn from in scene 4's data
    (0x16FE, 0x18A2, 0xA600, (4,)),             # $BCFE-$BEA1
]
# bank 15's split pointer tables whose targets are scene code: on the XEGS they
# mean "that address in whichever code bank is loaded", so each scene page gets
# its own copy of the high bytes, relocated for that scene, and bank 15 reads
# that. (high table, low table, entries, the copy's address in every scene page)
SCENE_TABLES = [
    (0xBE5A, 0xBE3F, 27, 0x81C0),     # sprite pointers ($BED6): entries 0-19 the intro
                                      # cutscene's, 20-26 scenes 2-4's
]
SP_PAGEMAP = 0x81A0

# ------------------------------------------- sprites copied to the fixed bank
# scene-code sprite runs (read as blit sources in scenes 0, 2, 3, 4; identical
# bytes wherever two scenes read the same address) and the health arrows.
# (XEGS start, end exclusive, page delta, scenes)
SPRITE_COPIES = [
    (0x1200, 0x1524, 0xE300, (0, 2, 3, 4)),     # $F500-$F823: from $1200, since
                                                # scene 3's floor stripes (9x22)
                                                # start with their header in the
                                                # engine's last three bytes
    (0x1530, 0x15B3, 0xE300, (3, 4)),           # $F830-$F8B2
    (0x1600, 0x16FE, 0xE300, (2, 3, 4)),        # $F900-$F9FD
    (0x16FE, 0x18A2, 0xE300, (2, 3)),           # $F9FE-$FBA1: scene 4 has its
                                                # own sprites here (the finale's;
                                                # ART_COPIES)
    (0x18BF, 0x18D8, 0xE300, (2, 3, 4)),        # $FBBF-$FBD7
    (0x1C80, 0x1CFA, 0xE000, (4,)),             # $FC80-$FCF9 (to $1CF9: the
                                                # 5x2 frame at $1CEE, scene 4)
    (0x1F00, 0x1F29, 0xDE00, (4,)),             # $FD00-$FD28
    (0x1FD7, 0x1FFD, 0xDE00, (4,)),             # $FDD7-$FDFC
    (0x2193, 0x2276, 0xDD00, (0,)),             # $FE93-$FF75
    (0x0B12, 0x0B25, 0xF300, SCENES),           # health arrows, $FE12-$FE24
]

# ------------------------------------------------------------- zero page
FREE_ZP = [0x49, 0x63, 0x64, 0x6E, 0x73, 0x74, 0x7E, 0x8E, 0x9B, 0x9C, 0x9D,
           0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB,
           0xCC, 0xCD, 0xCE, 0xCF, 0xD1, 0xD3, 0xD4, 0xD5, 0xD6, 0xDA, 0xE9,
           0xEC, 0xF3, 0xF4, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]
# used only by bank 15, so moving them to absolute RAM grows only bank 15
MOVERS = [0x26, 0x27, 0x28, 0x2B, 0x2C, 0x32, 0x3A, 0x3C, 0x3D,
          0x6C, 0x6D, 0x7A, 0x7C, 0x7D, 0x8A, 0x9E, 0x9F, 0xA6]
MOVER_BASE = 0x1800
PINNED = {0x00: 0xC6, 0x01: 0xC7, 0x02: 0xC8, 0x03: 0xC9, 0x04: 0xCA,
          0x05: 0xCB, 0x06: 0xCC, 0x07: 0xCD,           # overlapping pointers
          0x0A: 0xCE, 0x0B: 0xCF, 0x0D: 0xD3, 0x0E: 0xD4,
          0x14: 0xD5, 0x15: 0xD6}
# zero-page bytes the game never references still need a home for the
# swap and clear loops: a scratch block
ZP_SCRATCH = 0x1820


def zero_page_map(usage):
    """XEGS zero page -> 7800 address, for all 256 bytes.

    usage: {xegs zp: reference count}, to give the busiest bytes the zero-page
    slots. $40-$FF stay where they are unless they are movers."""
    out = {}
    for i, z in enumerate(MOVERS):
        out[z] = MOVER_BASE + i
    out.update(PINNED)
    slots = [z for z in FREE_ZP if z not in PINNED.values()] + [z for z in MOVERS if z >= 0x40]
    need = [z for z in range(0x40) if z not in out and usage.get(z)]
    need.sort(key=lambda z: -usage.get(z, 0))
    if len(need) > len(slots):
        raise SystemExit("zero page: %d bytes for %d slots" % (len(need), len(slots)))
    for z, slot in zip(need, sorted(slots)):
        out[z] = slot
    scratch = ZP_SCRATCH
    taken = set(out.values())
    for z in range(0x100):
        if z not in out:
            # unused by the game: itself, unless that address now holds another
            # byte (the swap and clear loops walk all of $00-$7F)
            out[z] = z if (z >= 0x40 and z not in taken) else None
        if out[z] is None:
            out[z] = scratch
            scratch += 1
    return out


# ------------------------------------------------- system RAM and shadows
SYS = 0x1E00                      # system variables (console RAM)
SYSVARS = [                       # name, size
    ("S_BANK", 1),                # the bank now in the window
    ("S_SCENEBANK", 1),           # the scene page
    ("S_NMICOUNT", 1),            # interrupts so far this frame
    ("S_NMIVBI", 1),              # the count at which the VBI zone fires
    ("S_DLIST", 2),               # DLISTL/H as the game wrote them
    ("S_DLIST_A", 2),             # the XEGS display list the A-list was built for
    ("S_DLIST_B", 2),
    ("S_NMIEN", 1), ("S_NMIRES", 1), ("S_DMACTL", 1), ("S_CONSOL", 1),
    ("S_PORTA", 1), ("S_LATCH", 1), ("S_SINK", 1), ("S_VCOUNT", 1),
    ("S_CTRL", 1),                # MARIA CTRL for the list being shown
    ("S_TMP", 4),
    ("S_POKEY", 16),              # POKEY register shadow ($D200-$D20F)
    ("S_VDSLST", 2), ("S_VIMIRQ", 2), ("S_VVBLKI", 2),
    ("S_SDMCTL", 1), ("S_SDLST", 2), ("S_SSKCTL", 1), ("S_COLDST", 1),
    ("S_OS033B", 1),
    ("S_FRAMES", 1),              # vertical-blank stand-ins so far
    ("S_VBI_A", 1), ("S_VBI_B", 1),   # NMI count at which each list's VBI fires
    ("S_DLIDX", 1),               # table index of the list being built or shown
    ("S_ROWBASE", 2), ("S_ROWP", 2), ("S_STEP", 1), ("S_FLAG", 1),
    ("S_LINES", 1), ("S_NDLI", 1), ("S_KIND", 1), ("S_COUNT", 1), ("S_ARG", 1),
    ("S_SND04", 1),               # $04 kept across the sound starter
    ("S_BUSY", 1),                # Frame is running (it must not re-enter)
    ("S_PEND", 1),                # a list chosen but not yet shown
    ("S_PDPPL", 1), ("S_PDPPH", 1), ("S_PCTRL", 1), ("S_PVBI", 1), ("S_PM8", 1), ("S_PIDX", 1),
    ("S_INVBI", 1),               # the vertical blank is running (it never nests)
    ("S_BTMP", 2),                # the list builder's scratch
    ("S_INDLI", 1),               # the game's DLI handler is running
    ("S_M8B", 1), ("S_M8Y", 1),   # Mode8's scratch
    ("S_M8COPY", 30),             # the mode-8 source bytes last widened
    ("S_PBLANK", 1), ("S_SHOWBLANK", 1),   # the blank list is chosen / on screen
    ("S_RSWCHA", 1), ("S_RSWCHB", 1),     # RIOT, read in vertical blank
    ("S_BTX", 1),                 # BlitBank keeps the blitter's X here
    ("S_SN", 2), ("S_SSTEP", 1), ("S_SCH", 1), ("S_SVOL", 1), ("S_SF", 1),   # TiaSound's scratch
    ("S_VBIPEND", 1),             # a vertical blank waits for it to end
    ("S_DLIPEND", 1),             # a DLI waits for the one running to end
    ("S_CHOSEN", 3),              # the list Frame last chose, and its DMA bit
    # the status bar's cache (FINDINGS "The health arrows, drawn only when
    # they change"): per buffer (A, B) the player's and the foe's health last
    # drawn there ($FF: unknown; foe $FE: none drawn), this picture's state
    ("S_STP", 2), ("S_STF", 2),
    ("S_STDEF", 1),               # this picture's clear is deferred
    ("S_STFSEEN", 1),             # this picture called the foe's arrows
    ("S_STTOUCH", 1),             # other drawing touched the status rows
    ("S_STINS", 1),               # the status bar's own drawing is running
    # the column routine's (FINDINGS "The tiny sprites are columns"): the
    # loop's limit, X and Y, the template piece's rows, bytes a row, and
    # per byte what to keep of the screen (K) and what to put there (T),
    # 8 a row; the pieces' first row and the rows this one draws
    ("S_CLIM", 1), ("S_CX", 1), ("S_CY", 1), ("S_CNONE", 1),
    ("S_CH", 1), ("S_CNB", 1), ("S_CJ", 1), ("S_CHH", 1), ("S_CR", 1),
    ("S_CT", 16), ("S_CK", 16),
    # the fast fill's (FINDINGS "The fast fill"): the value, the row stride
    # (40, or 80 for the pattern's passes), rows, whole blocks left,
    # scratch, and the pattern's start
    ("S_FVAL", 1), ("S_FSTRIDE", 1), ("S_FCOUNT", 1), ("S_FK", 1), ("S_FT", 1),
    ("S_FP0", 2),
    ("S_CLIPROW", 48),            # RowBase's scratch row: a draw that starts
                                  # below the bottom lands here (col + width
                                  # <= 40, plus the edge byte and blitter B's -1)
]


def sysvars():
    out, a = {}, SYS
    for name, n in SYSVARS:
        out[name] = a
        a += n
    assert a <= 0x1F00, "system variables run into the mode-8 rows"
    return out


MODE8_ROWS = 0x1F00               # 3 rows x 40 bytes, expanded each frame
DLL_A = 0x2200                    # display list lists, one per framebuffer
DLL_B = 0x24E0

# hardware and OS symbols, as xesource.py names them -> 7800 address
def hw_map(sv):
    return {
        "COLPF0": 0x25, "COLPF1": 0x26, "COLPF2": 0x27, "COLPF3": 0x28,   # palette 1
        "COLBK": 0x20, "TRIG0": 0x0C, "TRIG1": 0x0D, "WSYNC": 0x24,
        "CONSOL": sv["S_CONSOL"], "HITCLR": sv["S_SINK"], "HPOSP0": sv["S_SINK"],
        "ST_P": sv["S_STP"], "ST_TOUCH": sv["S_STTOUCH"],   # the status bar's cache
        "FL_VAL": sv["S_FVAL"], "FL_STRIDE": sv["S_FSTRIDE"], "FL_COUNT": sv["S_FCOUNT"],   # the fast fill
        "PORTA": sv["S_PORTA"], "PORTB": sv["S_SINK"], "PACTL": sv["S_SINK"], "PBCTL": sv["S_SINK"],
        "DMACTL": sv["S_DMACTL"], "CHACTL": sv["S_SINK"], "DLISTL": sv["S_DLIST"],
        "DLISTH": sv["S_DLIST"] + 1, "HSCROL": sv["S_SINK"], "VSCROL": sv["S_SINK"],
        "PMBASE": sv["S_SINK"], "CHBASE": sv["S_SINK"], "VCOUNT": sv["S_VCOUNT"],
        "NMIEN": sv["S_NMIEN"], "NMIRES": sv["S_NMIRES"], "BANKSEL": sv["S_SINK"],
        "AUDF1": sv["S_POKEY"] + 0, "AUDC1": sv["S_POKEY"] + 1, "AUDF2": sv["S_POKEY"] + 2,
        "AUDC2": sv["S_POKEY"] + 3, "AUDF3": sv["S_POKEY"] + 4, "AUDC3": sv["S_POKEY"] + 5,
        "AUDF4": sv["S_POKEY"] + 6, "AUDC4": sv["S_POKEY"] + 7, "AUDCTL": sv["S_POKEY"] + 8,
        "KBCODE": sv["S_POKEY"] + 9, "RANDOM": sv["S_POKEY"] + 10,
        "IRQEN": sv["S_POKEY"] + 14, "SKCTL": sv["S_POKEY"] + 15,
        # OS page shadows the game uses
        "V_0200": sv["S_VDSLST"], "V_0201": sv["S_VDSLST"] + 1,
        "V_0216": sv["S_VIMIRQ"], "V_0217": sv["S_VIMIRQ"] + 1,
        "V_0222": sv["S_VVBLKI"], "V_0223": sv["S_VVBLKI"] + 1,
        "V_022F": sv["S_SDMCTL"], "V_0230": sv["S_SDLST"], "V_0231": sv["S_SDLST"] + 1,
        "V_0232": sv["S_SSKCTL"], "V_0244": sv["S_COLDST"], "V_033B": sv["S_OS033B"],
        # the clear loop's self-modified store: operand high byte set at run time
        "OS_FF00": 0xFF00,
    }


# ----------------------------------------------------------- replacements
# XEGS address -> (end exclusive, lines). Outside bank 15 a replacement must
# assemble to exactly the bytes it replaces (the linker checks).
NOP = "    NOP"


def pad(lines, size_so_far, size):
    return lines + [NOP] * (size - size_so_far)


def unrolled(src_base, dst_base, n, x_after, src_sym, dst_sym):
    """A 16-byte record copy, unrolled so the bytes can live anywhere."""
    out = []
    for i in range(n):
        out.append("    LDA %s" % src_sym(src_base + i))
        out.append("    STA %s" % dst_sym(dst_base + i))
    out.append("    LDX #$%02X" % x_after)
    return out


def replacements(scene=None):
    z = lambda a: "Z_%02X" % a
    v47 = lambda a: "V_47F7+%d" % (a - 0x47F7) if a != 0x47F7 else "V_47F7"
    r = {
        # zero-page swap and clear: same-size jumps to system routines
        0x1159: (0x1169, pad(["    JMP SysZpSwap"], 3, 16)),
        0x2E59: (0x2E69, pad(["    JMP SysZpSwap"], 3, 16)),
        0x0EAA: (0x0EB4, pad(["    JMP SysZpClear"], 3, 10)),
        # the loader: $2F5A loads everything, $2F66 the scene's banks
        0x2F5A: (0x2F66, pad(["    JSR SysLoadCommon"], 3, 12)),
        0x2F66: (0x2F8A, pad(["    JMP SysLoadScene"], 3, 36)),
        # wait for scanline 200
        0x2F8A: (0x2F91, pad(["    JSR SysWaitLine200"], 3, 7)),
        # $0FFB (vertical-blank step 8) starts in the common bank and runs on
        # into the engine at $1000; on the 7800 those are apart
        0x0FFB: (0x1000, pad(["    JMP SysCommonTail"], 3, 5)),
        # bug fix: the sound-effect starter uses $04/$05 as its own pointer and
        # leaves $04 (the blitter's source high byte) at $F8; a text blit that
        # only reloads $03 then draws OS code as dots. SysSound keeps $04.
        0x2422: (0x2426, pad(["    JMP SysSound"], 3, 4)),
        # the game picks its display list here ($0F87 ... $0F93 STA DLISTH / RTS):
        # pick the MARIA list at the same moment
        0x0F93: (0x0F97, pad(["    JMP SysSetDlist"], 3, 4)),
        # the stick
        0x0990: (0x0993, ["    JSR SysReadStick"]),
        0xAD09: (0xAD0C, ["    JSR SysReadStick"]),
        # blit bank switching: pick the bank from the source pointer, and
        # give the scene page back when the pointer is restored
        0x29DC: (0x29E0, pad(["    JSR SysBlitBank"], 3, 4)),
        0x29FF: (0x2A04, pad(["    JMP SysBlitDone"], 3, 5)),
        # bug fix: the row address ($2D46: row = Y - 35, times 40, plus the
        # buffer) has no bottom check, and the blitters and fills go on 40
        # bytes a row for as many rows as asked. A sprite partly below the
        # screen (the cutscene) wrote past the buffer: on the XEGS into scene
        # data RAM at $6000 (or, from buffer B, into the top of buffer A), on
        # the 7800 into the engine at $7000, which then crashed. SysRowBase
        # stops every draw at the last row (FINDINGS "Drawing below the
        # screen").
        # (the first 16 bytes, up to the multiply; the buffer base after it
        # stays the game's)
        0x2D46: (0x2D56, pad(["    JSR SysRowBase"], 3, 16)),
        # speed (enhancement): the fills' store loops, 11 cycles a byte row by
        # row, done 8 rows at a time column by column (STA abs,X, 5 a byte)
        # by the code in cart RAM at $7203 (sys7800.asm, ;;; RAMFILL). The
        # setup before ($2DA4, RowBase, the column) and the exit after ($17,
        # $06) stay the game's. The rectangle: its value, stride 40 and row
        # count, then the passes. The pattern: to the RAM code, and here the
        # 4-row store block it patches (at $2D19; the BPL's operand is set
        # for each block). FINDINGS "The fast fill"
        0x2CE0: (0x2CFB, pad(["    LDA Z_02", "    STA FL_VAL", "    LDA #40", "    STA FL_STRIDE",
                              "    LDA Z_0D", "    STA FL_COUNT", "    JSR RfPass", "    JMP L_2CFB"], 21, 27)),
        0x2D16: (0x2D3E, pad(["    JMP RfPattern"] + ["    STA $FFFF,X"] * 4 +
                             ["    DEX", "    .byte $10,$F1", "    RTS"], 19, 40)),
        # speed (enhancement): the row times 40. The game's $2D78 is a
        # general 8x8 shift-and-add multiply ($2DA1 x $2DA2, 8 turns, about
        # 290 cycles), and every draw call pays it. Its only caller is the
        # row address, always with 40 (the jump-table entry $2CC6 has no
        # caller in any scene), so: (4r + r) x 8, about 60 cycles. It leaves
        # $2DA1-$2DA3 as they were, which nothing reads (FINDINGS "The row
        # address, faster")
        0x2D78: (0x2DA1, pad(["    LDA #$00", "    STA Z_15",
                              "    LDA L_2DA1", "    ASL A", "    ROL Z_15",
                              "    ASL A", "    ROL Z_15",           # 4r
                              "    CLC", "    ADC L_2DA1", "    BCC RowTimes8",
                              "    INC Z_15",                         # 5r
                              "RowTimes8:", "    ASL A", "    ROL Z_15", "    ASL A", "    ROL Z_15",
                              "    ASL A", "    ROL Z_15",           # 40r
                              "    STA Z_14", "    RTS"], 33, 41)),
        # the status bar (enhancement): its three entries go through the
        # cache, which draws only what changed; the picture's end settles
        # it; the full clear and the buffer copy mark it stale (FINDINGS
        # "The health arrows, drawn only when they change")
        0x0B00: (0x0B03, ["    JMP ScStClear"]),
        0x0B03: (0x0B06, ["    JMP ScStPlayer"]),
        0x0B06: (0x0B09, ["    JMP ScStFoe"]),
        # (same size: bank 15 has no room to grow; $B60F's LDA $0AFE is done
        # by ScStFlipL, whose RTS leaves the flags; $AD80, the buffer copy's
        # routine, starts with JSR $B60F)
        0xB60F: (0xB612, ["    JSR ScStFlipL"]),
        0xAD80: (0xAD83, ["    JSR ScStCopy"]),
        0x280F: (0x2813, ["    JSR SysStClr", "    NOP"]),
        # the game's DLI handler ($1026) ends PLA/TAY/PLA/TAX/PLA/RTI; the
        # port enters it straight from the NMI (no second interrupt frame) and
        # takes it out through DliExit, which does the NMI's end-of-DLI work
        # (FINDINGS "The NMI's cost")
        0x1034: (0x103A, pad(["    JMP SysDliExit"], 3, 6)),
        # self-modifying code: the blitter writes its own (zp),Y operand at
        # $2926 and $2B11 (the mode byte before it picks ORA, AND or STA); the
        # value is the address of $14, which has moved (FINDINGS, "zero-page
        # operands written into code")
        0x289B: (0x289D, ["    LDA #<Z_14"]),
        0x2A6D: (0x2A6F, ["    LDA #<Z_14"]),
        # NMIEN is write-only: on the XEGS "LDA NMIEN / ORA #$80 / STA NMIEN"
        # reads $FF and so turns the vertical blank on as well as DLIs (the
        # scene loader had turned both off). The port's NMIEN is a readable
        # shadow, so read what the XEGS reads (FINDINGS, "Scene 1")
        0x0EA1: (0x0EA4, ["    LDA #$FF", "    NOP"]),
        # the keyboard, gone (there is none): every read of it and the code only
        # they reach. The console keys cover what matters (START restarts, at
        # the ending too; SELECT pauses; FINDINGS, "The keyboard comes out").
        # The move dispatch at $AE78 takes the key code in A (0 when no key)
        # and, on the same path, the joystick's fire flags ($47 punch, $46
        # kick): Space and + * (walk) in walking mode; Q A Z, W S X (the moves
        # by key) and B (bow) after $AEAB, all compared against A. With no
        # keyboard A is always 0 there, so the key tests go and the joystick
        # branches ($AED0, $AEF7, $AF1B, $AF27) stay; the bow by joystick (up
        # and fire) is unaffected. The exit $AEB1 is every move's and stays.
        0xAE78: (0xAEAB, ["    LDA #$00"]),
        0xAEC4: (0xAED0, ["    JMP L_AEE5"]),
        0xAED5: (0xAEE5, []),
        0xAEEB: (0xAEF7, ["    JMP L_AF33"]),
        0xAEFC: (0xAF0F, []),
        0xAF20: (0xAF24, []),
        0xAF2C: (0xAF33, []),
        # play: Esc (pause), J/K (joystick or keys), Ctrl-R (next scene) and
        # Ctrl-N (enemy health 1), the last two developer cheats
        0xB71E: (0xB773, ["    RTS"]),
        0xB773: (0xB780, []),
        # the Esc pause loop, reached only from those
        0xB785: (0xB7B1, []),
        # the vertical blank's key repeat (SKSTAT), keeping its $F2 countdown
        0x1004: (0x101F, pad(["    RTS"], 1, 27)),
        # the keyboard interrupt: IRQST and KBCODE (the 7800 raises no IRQ)
        0x10FE: (0x1123, pad(["    PLA", "    RTI"], 2, 37)),
        # dead XEGS code the port replaces, removed to make room in the fixed
        # bank (bank 15 may change size): the 8K copy routine (called only by
        # the boot and the loader) and the cartridge boot itself
        0xB2CC: (0xB2EC, []),
        0xB7B1: (0xB7DB, []),
        # bank 15's record copies, unrolled (bank 15 may grow)
        0xB071: (0xB07C, unrolled(0x20, 0x70, 16, 0x10, z, z)),
        0xB07D: (0xB088, unrolled(0x70, 0x20, 16, 0x10, z, z)),
        0xB08D: (0xB098, unrolled(0x20, 0x60, 16, 0x10, z, z)),
        0xB099: (0xB0A4, unrolled(0x60, 0x20, 16, 0x10, z, z)),
        0xBA73: (0xBA7D, unrolled(0x70, 0x47F7, 16, 0xFF, z, v47)),
        0xBA7E: (0xBA88, unrolled(0x47F7, 0x70, 16, 0xFF, v47, z)),
    }
    r.update(SCENE_REPLACEMENTS.get(scene, {}))
    return r


# replacements in one scene's own code or data only
SCENE_REPLACEMENTS = {
    # the ending waits for Ctrl-R to restart; without the keyboard it just
    # loops on the console check ($B603), where START restarts
    4: {0x7883: (0x7898, pad(["    JMP L_7876"], 3, 21))},
}


def column_loop(lim, entry):
    """One of level 1's column loops (INC $06 / INC $06 / JSR piece / LDA
    $06 / CMP #lim / BCC, 13 bytes) as a call to the scene page's column
    routine, which draws the same pieces faster. A and the flags end as the
    loop's did."""
    return pad(["    LDA #$%02X" % lim, "    JSR %s" % entry,
                "    LDA Z_06", "    CMP #$%02X" % lim], 9, 13)


# speed (enhancement): level 1 draws its posts and pillars as columns of
# 1- or 2-row pieces 2 rows apart, one blit call a piece (FINDINGS "The tiny
# sprites are columns"). Scene 6 (Select) has the same code; scene 0's copy
# calls the engine directly and is left alone.
COLUMN_LOOPS = {
    0x6EFB: (0x66, "ScCol68"), 0x6F17: (0x97, "ScCol68"),
    0x6F3D: (0x66, "ScCol68"), 0x6F6B: (0xAA, "ScCol68"),
    0x71A5: (0x97, "ScColA"), 0x7CC0: (0x95, "ScColA"), 0x7CF8: (0x93, "ScColA"),
}
LEVEL1_SCENES = (1, 6)        # their scene pages hold the column routine
for _sc in LEVEL1_SCENES:
    SCENE_REPLACEMENTS.setdefault(_sc, {}).update(
        {a: (a + 13, column_loop(lim, entry)) for a, (lim, entry) in COLUMN_LOOPS.items()})
