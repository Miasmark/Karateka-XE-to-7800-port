#!/usr/bin/env python3
"""
Build the 7800 cartridge of XEGS Karateka: 128K SuperGame + 16K RAM at
$4000 (header type $0006, the Summer Games board), signed.

    python port/build7800.py -o work/karateka7800.a78

Banks (port/layout7800.py):
  0-5  scene pages 0, 1, 2, 3, 4, 6: system data $8000-$8202 (the engine's
       seven per-scene bytes, scene-data carve-outs, display-list tables and
       descriptions), scene code $8203, common $96E8, scene data $A000
  6    art $8000, then the RAM images: engine $A000/$A203, small sprites
  7    fixed: bank 15 $C000, system code $E230 (jump table first), the
       per-row display lists, sprite copies, signature and vectors

Every byte of the cartridge is placed through one map that refuses overlaps.
The result contains cartridge data: it goes under work/ (ignored), never
into the repository.
"""
import argparse
import glob
import json
import re
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import dis as D          # noqa: E402
import asm               # noqa: E402
import sign7800          # noqa: E402  (the toolkit's, on the path via xesource)

BANK = 0x4000
FBA_BASE, FBB_BASE = 0x5808, 0x4010     # row 0 of each buffer on the 7800
ROWS = 153
DLL_LINES = 243
SPRITE_TAIL = (0x06E8, 0x06F6)   # the hyphen glyph after the small-sprite block
SND_OFFSET = 0               # the TIA music's transposition in cents (port/sndconv.py)
SMALL_DLS = 0xF8B4              # the empty and mode-8 row DLs, in a sprite-copy gap
VBI_LINE = DLL_LINES - 2   # the line whose DLI stands in for the vertical blank
VBI_MARGIN = 16            # lines every list's last DLI must leave before VBI_LINE
GAME_DLIS = 6              # every XEGS list has six DLIs; the NMI count relies on it
BLANK_DLIS = (31, 85, 126, 137, 180, 193)   # the blank list's dummy DLIs, at the
                                            # lines most game lists use
SIG_START = 0xFF80          # $FF80-$FFF7: the NTSC signature, written by the signer
                            # after everything is placed; free-space searches stop here
VBI_SPIN = 110             # turns of an 11-cycle loop the vertical blank waits for
# instructions the patch kit's options edit (port/mkkit.py; FINDINGS, "A build
# without MAME"), as XEGS addresses and the scenes whose banks hold them; the
# build writes their 7800 addresses to karateka7800.sites.json. Scene 0 (the
# title and attract sequence) is left alone throughout, as xe-easy.lua does.
PATCH_SITES = [      # (name, XEGS label, offset from it, scenes)
    ("player-damage", 0x0BDD, 8, (1, 2, 3, 4, 6)),   # DEC $B6 / BNE $0BED
    ("foe-damage", 0x0BEE, 8, (1, 2, 3, 4, 6)),      # DEC $B7 / BNE $0BFE
    ("instant-death", 0xB12A, 4, (1,)),              # BEQ $B131 (bank 15, shared)
    ("gate", 0x79C5, 0, (2,)),                       # LDA $A7 (is the gate low enough)
    ("cliff", 0x7914, 0, (1, 6)),                    # LDA $A2 (driven over the edge)
    ("game-start", 0x7806, 1, (0,)),                 # LDA #$01 / STA $D0: the first scene
]
                           # MSTAT (about 10 lines; it needs about 2)
PAL = 1                                  # the palette COLPF0-2 are mapped to
HW = {"INPTCTRL": 0x01, "AUDC0": 0x15, "AUDC1": 0x16, "AUDF0": 0x17, "AUDF1": 0x18,
      "AUDV0": 0x19, "AUDV1": 0x1A, "BACKGRND": 0x20, "WSYNC": 0x24,
      "MSTAT": 0x28, "DPPH": 0x2C, "DPPL": 0x30, "CTRL": 0x3C, "SWCHA": 0x280,
      "SWCHB": 0x282, "CTLSWA": 0x281, "BANKSEL": 0x8000}
SP = {"SP_ENGINE7": 0x8000, "SP_NCARVE": 0x8007, "SP_CARVE": 0x8008,
      "SP_NDL": 0x8040, "DLT_LO": 0x8041, "DLT_HI": 0x8049, "DLT_BUF": 0x8051,
      "DLT_CTRL": 0x8059, "DLT_DLO": 0x8061, "DLT_DHI": 0x8069, "DLT_M8": 0x8071,
      "SP_DESC": 0x8080}
IMG = {"IMG_ENGINE1": 0xA000, "IMG_ENGINE2": 0xA203, "IMG_SPRITES": 0xAF03}


class Image(object):
    """One 16K bank; place() refuses to overwrite anything placed before."""

    def __init__(self, name, base):
        self.name, self.base = name, base
        self.data = bytearray([0xFF]) * BANK
        self.used = bytearray(BANK)

    def place(self, addr, data, what):
        off = addr - self.base
        if off < 0 or off + len(data) > BANK:
            raise SystemExit("%s: %s ($%04X, %d bytes) outside the bank" % (self.name, what, addr, len(data)))
        for i in range(len(data)):
            if self.used[off + i]:
                raise SystemExit("%s: %s overlaps something at $%04X" % (self.name, what, addr + i))
        self.data[off:off + len(data)] = data
        for i in range(len(data)):
            self.used[off + i] = 1

    def find(self, size, lo, hi):
        """The lowest free run of `size` bytes in [lo, hi), or None."""
        run = 0
        for a in range(lo, hi):
            run = 0 if self.used[a - self.base] else run + 1
            if run == size:
                return a - size + 1
        return None


# ------------------------------------------------------- display lists
def row_dl(base, r):
    a = base + 40 * r
    b = a + 20
    w = (PAL << 5) | ((-20) & 0x1F)
    return bytes([a & 0xFF, w, a >> 8, 0x00, b & 0xFF, w, b >> 8, 80, 0x00, 0x00])


def xe_display_lists():
    """{scene: set of XEGS display list addresses the game selected}."""
    used = {}
    for p in glob.glob(os.path.join(K.ROOT, "census", "*.col")):
        lo = None
        for line in open(p):
            parts = line.split()
            if len(parts) < 5:
                continue
            s, reg, val = int(parts[0]), parts[3], int(parts[4], 16)
            if reg == "D402":
                lo = val
            elif reg == "D403" and lo is not None:
                used.setdefault(s, set()).add(val * 256 + lo)
    return used


def list_fits(mem, at):
    """This scene holds a list at `at` the port can show: it parses, has the
    game's six DLIs, and ends above the vertical blank stand-in."""
    try:
        d = describe(mem, at)[0]
    except SystemExit:
        return False
    line, last_dli = 0, -1
    for i in range(0, len(d) - 1, 3):
        line += d[i + 1]
        if d[i] & 0x80:
            last_dli = line - 1
    ndli = sum(1 for i in range(0, len(d) - 1, 3) if d[i] & 0x80)
    return ndli == GAME_DLIS and line <= VBI_LINE and last_dli <= VBI_LINE - VBI_MARGIN


def shared_display_lists(used, mems):
    """The census lists, plus every list another scene's census saw that
    this scene also holds as a valid list (its own version of it, which may
    differ: scene 0's $19B3 has a DLI ten lines lower than scene 1's). Paths
    no census run took use them: scene 0's attract sequence shows $19B3 after
    the cutscene, and without it the port showed the blank list on those
    frames (FINDINGS "Flashing black after the story")."""
    out = {s: set(v) for s, v in used.items()}
    every = set().union(*used.values())
    for s in used:
        for at in every - out[s]:
            if list_fits(mems[s], at):
                out[s].add(at)
    return out


def describe(mem, at):
    """An XEGS display list as runs: (kind|DLI, lines, argument), plus which
    buffer, whether it is mode F (320A) and whether it has mode-8 rows."""
    runs, pc, addr, buf, modef, m8 = [], at, 0, None, False, False
    m8row = 0
    for _ in range(400):
        ins = mem.get(pc, 0)
        mode, dli, lms = ins & 0x0F, bool(ins & 0x80), bool(ins & 0x40)
        if mode == 0:
            runs.append([0, ((ins >> 4) & 7) + 1, 0, dli])
            pc += 1
            continue
        if mode == 1:
            break
        if lms:
            addr = mem.get(pc + 1, 0) | mem.get(pc + 2, 0) << 8
            pc += 3
        else:
            pc += 1
        b = "A" if 0x4800 <= addr < 0x6000 else ("B" if 0x3000 <= addr < 0x4800 else None)
        if b is None:
            raise SystemExit("display list $%04X shows $%04X, not a framebuffer" % (at, addr))
        if buf and b != buf:
            raise SystemExit("display list $%04X mixes buffers" % at)
        buf = b
        if mode == 0x8:
            runs.append([1, 8, m8row, dli])
            m8row += 1
            m8 = True
            addr += 10
        elif mode in (0xE, 0xF):
            row = (addr - (0x4808 if b == "A" else 0x3010)) // 40
            if runs and runs[-1][0] == 2 and not runs[-1][3] and runs[-1][2] + runs[-1][1] == row:
                runs[-1][1] += 1
                runs[-1][3] = dli
            else:
                runs.append([2, 1, row, dli])
            modef = modef or mode == 0xF
            addr += 40
        else:
            raise SystemExit("display list $%04X: ANTIC mode %X not handled" % (at, mode))
    out = bytearray()
    for kind, n, arg, dli in runs:
        out += bytes([kind | (0x80 if dli else 0), n, arg])
    out.append(0xFF)
    return bytes(out), buf, modef, m8


# ------------------------------------------------------------------ build
def build(out_path):
    link = K.link(verbose=False)
    zp = link["zp"]
    sv = L.sysvars()
    res1 = link["scenes"][1]["resolver"]
    res0 = link["scenes"][0]["resolver"]
    banks = {b: Image("bank %d" % b, 0x8000) for b in range(7)}
    fixed = Image("fixed", 0xC000)

    # --- fixed bank: bank 15, sprite copies
    org, b15 = link["shared"]["bank15"]
    fixed.place(org, b15, "bank 15")
    mem = {s: D.memory(s) for s in L.SCENES}
    for lo, hi, d, scenes in L.SPRITE_COPIES:
        src = mem[scenes[0]]
        for s in scenes[1:]:
            if any(mem[s][a] != src[a] for a in range(lo, hi)):
                # a shared copy must hold every listed scene's bytes: "the
                # same where read" was only as good as the census's reading
                # (scene 4's finale frames at $16FE-$18A1 came out as scene 2's)
                raise SystemExit("sprite copy $%04X-$%04X: scene %d's bytes differ from scene %d's"
                                 % (lo, hi - 1, s, scenes[0]))
        fixed.place(lo + d, bytes(src[a] for a in range(lo, hi)), "sprite copy $%04X" % lo)
    for lo, hi, d, scenes in L.ART_COPIES:
        for s in scenes[1:]:
            if any(mem[s][a] != mem[scenes[0]][a] for a in range(lo, hi)):
                raise SystemExit("art-bank copy $%04X-$%04X: scene %d's bytes differ from scene %d's"
                                 % (lo, hi - 1, s, scenes[0]))
        banks[L.ART_BANK].place(lo + d, bytes(mem[scenes[0]][a] for a in range(lo, hi)),
                                "art-bank sprite copy $%04X" % lo)

    # --- the display lists: one per framebuffer row, per buffer
    dls = bytearray()
    for base in (FBA_BASE, FBB_BASE):
        for r in range(ROWS):
            dls += row_dl(base, r)

    # --- per-scene pages
    xdl = shared_display_lists(xe_display_lists(), mem)
    for s in L.SCENES:
        page = banks[L.SCENE_BANK[s]]
        ch = link["scenes"][s]["chunks"]
        for name in ("scode", "common", "sdata"):
            org, data = ch[name]
            page.place(org, data, name)
        eng2 = ch["engine2"][1]
        page.place(SP["SP_ENGINE7"], eng2[0x24A5 - 0x2300:0x24AC - 0x2300], "engine bytes")
        carves = bytearray()
        for lo, hi, ram in L.CARVE_SDATA.get(s, []):
            # from where the range sits in the scene page (scene data or scene
            # code), in entries of at most 255 bytes
            src = lo + (0x4000 if lo >= 0x6000 else 0x7000)
            while lo < hi:
                n = min(hi - lo, 255)
                carves += bytes([src & 0xFF, src >> 8, ram & 0xFF, ram >> 8, n])
                lo, src, ram = lo + n, src + n, ram + n
        page.place(SP["SP_NCARVE"], bytes([len(carves)]), "carve count")
        if carves:
            page.place(SP["SP_CARVE"], carves, "carves")
        entries, desc = [], bytearray()
        for at in sorted(xdl.get(s, ())):
            d, buf, modef, m8 = describe(mem[s], at)
            line, last_dli = 0, -1
            for i in range(0, len(d) - 1, 3):
                line += d[i + 1]
                if d[i] & 0x80:
                    last_dli = line - 1
            ndli = sum(1 for i in range(0, len(d) - 1, 3) if d[i] & 0x80)
            if ndli != GAME_DLIS:
                raise SystemExit("scene %d list $%04X has %d DLIs; the NMI count assumes %d"
                                 % (s, at, ndli, GAME_DLIS))
            if line > VBI_LINE or last_dli > VBI_LINE - VBI_MARGIN:
                raise SystemExit("scene %d list $%04X: %d lines, last DLI on %d; the vertical blank "
                                 "stand-in is line %d" % (s, at, line, last_dli, VBI_LINE))
            addr = SP["SP_DESC"] + len(desc)
            entries.append((at, 0 if buf == "A" else 1, 0x43 if modef else 0x40, addr, 1 if m8 else 0))
            desc += d
        if len(entries) > 8:
            raise SystemExit("scene %d: %d display lists, tables hold 8" % (s, len(entries)))
        page.place(SP["SP_NDL"], bytes([len(entries)]), "DL count")
        for i, (at, buf, ctrl, addr, m8) in enumerate(entries):
            page.place(SP["DLT_LO"] + i, bytes([at & 0xFF]), "DLT")
            page.place(SP["DLT_HI"] + i, bytes([at >> 8]), "DLT")
            page.place(SP["DLT_BUF"] + i, bytes([buf]), "DLT")
            page.place(SP["DLT_CTRL"] + i, bytes([ctrl]), "DLT")
            page.place(SP["DLT_DLO"] + i, bytes([addr & 0xFF]), "DLT")
            page.place(SP["DLT_DHI"] + i, bytes([addr >> 8]), "DLT")
            page.place(SP["DLT_M8"] + i, bytes([m8]), "DLT")
        # the scene's page map: which of pages $A0-$BF are art-bank copies
        pmap = bytearray(32)
        for lo, hi, d, scenes in L.ART_COPIES:
            if s in scenes:
                for p in range((lo + d) >> 8, ((hi - 1 + d) >> 8) + 1):
                    pmap[p - 0xA0] = 1
        page.place(L.SP_PAGEMAP, bytes(pmap), "page map")
        # bank 15's scene-dependent pointer tables, relocated for this scene
        res = link["scenes"][s]["resolver"]
        for hi_t, lo_t, n, at in L.SCENE_TABLES:
            vals = bytearray()
            for i in range(n):
                tgt = mem[s][hi_t + i] << 8 | mem[s][lo_t + i]
                nt = res.new_addr(tgt)
                if (nt & 0xFF) != (tgt & 0xFF):
                    raise SystemExit("scene %d: table $%04X entry %d: $%04X moves to $%04X, not by whole pages"
                                     % (s, hi_t, i, tgt, nt))
                vals.append(nt >> 8)
            page.place(at, bytes(vals), "table $%04X" % hi_t)
        if SP["SP_DESC"] + len(desc) > L.SP_PAGEMAP:
            raise SystemExit("scene %d: descriptions run into the scene code" % s)
        page.place(SP["SP_DESC"], bytes(desc), "descriptions")

    # --- art bank
    art = banks[L.ART_BANK]
    org, data = link["shared"]["art"]
    art.place(org, data, "art")
    art.place(IMG["IMG_ENGINE1"], link["shared"]["engine1"][1], "engine image 1")
    e2 = bytearray(link["scenes"][0]["chunks"]["engine2"][1])
    art.place(IMG["IMG_ENGINE2"], bytes(e2), "engine image 2")
    # the small-sprite block's image, plus the 14 bytes after it: the story
    # font's hyphen glyph (character $7E, 12x1) sits at $06E8-$06F5, where the
    # common bank begins, and the renderer reaches it as $0480 + offset, so on
    # the 7800 it must follow the block in RAM too ($1DE8-$1DF5; the bytes stay
    # in the common bank as well, where the font table at $06F4 is read from).
    # It is the same in every scene. (Without it the hyphen in "self-concern"
    # read a zero-height header, and the blit ran 256 rows through the engine:
    # FINDINGS "Story crash".)
    tail = bytes(D.memory(0).get(a, 0) for a in range(SPRITE_TAIL[0], SPRITE_TAIL[1]))
    for s in L.SCENES:
        if bytes(D.memory(s).get(a, 0) for a in range(*SPRITE_TAIL)) != tail:
            raise SystemExit("the sprite-block tail $%04X-$%04X differs in scene %d" % (SPRITE_TAIL + (s,)))
    art.place(IMG["IMG_SPRITES"], link["shared"]["sprites"][1] + tail, "small-sprite image")

    # --- system code
    eq = dict(HW)
    eq.update(sv)
    eq.update(SP)
    eq.update(IMG)
    eq.update({
        "ZP_P1": zp[0x00], "ZP_P2": zp[0x02], "G_ZD0": zp[0xD0], "G_Z04": zp[0x04], "G_Z1C": zp[0x1C],
        "G_ENTRY0": res0.new_addr(0x7760), "G_L1000": res1.new_addr(0x1000),
        "G_L101F": res1.new_addr(0x101F), "G_L258D": res1.new_addr(0x258D),
        "G_L2426": res1.new_addr(0x2426), "G_L0F17": res1.new_addr(0x0F17),
        "G_L2D78": res1.new_addr(0x2D78), "G_L2DA1": res1.new_addr(0x2DA1), "G_L2DA2": res1.new_addr(0x2DA2),
        "G_Z06": zp[0x06], "G_Z07": zp[0x07], "G_Z0D": zp[0x0D], "G_Z14": zp[0x14], "G_Z15": zp[0x15],
        "G_ZB6": zp[0xB6], "G_ZB7": zp[0xB7], "ST_ROW": 146,        # the status bar's cache
        "G_Z05": zp[0x05], "G_Z0E": zp[0x0E], "G_Z0F": zp[0x0F], "G_Z10": zp[0x10],   # the column routine
        "G_Z16": zp[0x16], "G_Z1E": zp[0x1E], "G_Z1F": zp[0x1F], "G_Z52": zp[0x52],
        "G_L284E": res1.new_addr(0x284E), "G_L280C": res1.new_addr(0x280C),
        "G_Z02": zp[0x02], "G_Z12": zp[0x12], "G_L2D3E": res1.new_addr(0x2D3E),   # the fast fill
        "FILL_BLK": res1.new_addr(0x2D19), "FILL_BPL": res1.new_addr(0x2D27), "FILL_NEXT": res1.new_addr(0x2D28),
        "RAMFILL_AT": K.RAMFILL_TABLE,
        "G_L0B27": res1.new_addr(0x0B27), "G_L0B3E": res1.new_addr(0x0B3E), "G_L0B98": res1.new_addr(0x0B98),
        "G_L0AFE": res1.new_addr(0x0AFE), "G_LB60F": res1.new_addr(0xB60F),
        "FB_ROWS": ROWS, "CLIPROW": sv["S_CLIPROW"] + 1,   # +1: blitter B starts a byte early
        "ART_BANK": L.ART_BANK, "DLL_A": L.DLL_A, "DLL_B": L.DLL_B, "DLL_LINES": DLL_LINES, "VBI_LINE": VBI_LINE, "VBI_NMI": GAME_DLIS + 1,
        "VBI_SPIN": VBI_SPIN,
        "MODE8_ROWS": L.MODE8_ROWS, "FBA_ROW0": FBA_BASE, "FBB_ROW0": FBB_BASE,
        "SP_PAGEMAP": L.SP_PAGEMAP, "RAM_SPRITES": 0x1B80, "LEN_SPRITES": SPRITE_TAIL[1] - 0x0480,
        "RAM_ENGINE1": 0x7000, "LEN_ENGINE1": 0x1203 - 0x1000,
        "RAM_ENGINE2": 0x7300, "LEN_ENGINE2": 0x3000 - 0x2300, "RAM_ENGINE7": 0x74A5,
        "SWAPBUF": L.CARVE_COMMON[0][2],
    })
    # zero-page tables: XEGS $00-$7F by where they live now
    za, zb = [], []
    for z in range(0x80):
        t = zp[z]
        (za if t < 0x100 else zb).append((t, z))
    ccarve = bytearray()
    for lo, hi, ram in L.CARVE_COMMON:
        src = lo - 0x06E8 + 0x96E8
        ccarve += bytes([src & 0xFF, src >> 8, ram & 0xFF, ram >> 8, hi - lo])
    eq.update({"N_ZA": len(za), "N_ZB": len(zb), "N_CCARVE": len(L.CARVE_COMMON),
               "CCARVE_BYTES": len(ccarve)})
    src = open(os.path.join(HERE, "sys7800.asm")).read().replace("CPX #N_CCARVE*5", "CPX #CCARVE_BYTES")

    def by(vals):
        return ["    .byte " + ",".join("$%02X" % v for v in vals[i:i + 16]) for i in range(0, len(vals), 16)] or ["    .byte $00"]
    # the zero-page tables live in every scene page (the swap and clear run
    # with it selected), at $9300
    zpt = bytes([t for t, z in za] + [z for t, z in za] + [t - 0x1800 for t, z in zb] + [z for t, z in zb])
    eq.update({"ZPT_A": 0x9300, "ZPT_AX": 0x9300 + len(za), "ZPT_B": 0x9300 + 2 * len(za),
               "ZPT_BX": 0x9300 + 2 * len(za) + len(zb)})
    for s in L.SCENES:
        banks[L.SCENE_BANK[s]].place(0x9300, zpt, "zero-page tables")
    # the common-bank carve list and the scene-to-bank table: read by the
    # loaders, which always run with a scene page in; in every scene page
    sbt = bytes([L.SCENE_BANK.get(s, L.SCENE_BANK[0]) for s in range(7)])
    at = 0x9300 + len(zpt)
    eq.update({"CCARVE": at, "SCENEBANK_TAB": at + len(ccarve)})
    for s in L.SCENES:
        banks[L.SCENE_BANK[s]].place(at, bytes(ccarve) + sbt, "loader tables")
    # the empty DL and the three mode-8 row DLs: in the gap between sprite
    # copies at $F8B3-$F8FF (the system block has no room to spare)
    small = bytes([0, 0]) + b"".join(bytes(row_dl(L.MODE8_ROWS, k)) for k in range(3))
    eq.update({"DL_EMPTY": SMALL_DLS, "DL_M8": SMALL_DLS + 2})
    fixed.place(SMALL_DLS, small, "empty and mode-8 row DLs")
    # Mode8's tables, after them: a nibble's two 2-bit pixels, each widened
    # to a whole 160A byte (M8NIB_HI the left pixel, M8NIB_LO the right)
    widen = [0x00, 0x55, 0xAA, 0xFF]
    nib = bytes(widen[n >> 2] for n in range(16)) + bytes(widen[n & 3] for n in range(16))
    at = SMALL_DLS + len(small)
    eq.update({"M8NIB_HI": at, "M8NIB_LO": at + 16})
    fixed.place(at, nib, "mode-8 widening tables")
    # the blank list, in ROM: the six dummy DLIs and VBI_LINE as one-line zones
    # (MARIA raises a zone's DLI as the zone starts, so a flagged zone must be
    # exactly the flagged line, as in the game lists), the lines between them in
    # unflagged zones of up to 16 lines; so it has the game lists' seven NMIs,
    # on the same lines
    flagged = set(BLANK_DLIS + (VBI_LINE,))
    dll, line = bytearray(), 0
    while line < DLL_LINES:
        if line in flagged:
            h, dli = 1, 0x80
        else:
            nxt = min([e for e in flagged if e > line] or [DLL_LINES])
            h, dli = min(16, nxt - line), 0
        dll += bytes([dli | (h - 1), eq["DL_EMPTY"] >> 8, eq["DL_EMPTY"] & 0xFF])
        line += h
    where = fixed.find(len(dll), 0xF500, SIG_START)
    if where is None:
        raise SystemExit("fixed: no room for the blank list (%d bytes)" % len(dll))
    fixed.place(where, bytes(dll), "blank list")
    eq["BLANK_DLL"] = where
    # the POKEY-to-TIA sound tables (port/sndconv.py, SND_OFFSET), in free
    # gaps among the sprite copies (above $F500, clear of the system block)
    import sndconv
    for name, blob in sndconv.tables(SND_OFFSET).items():
        if name.startswith("="):
            eq[name[1:]] = blob
            continue
        where = fixed.find(len(blob), 0xF500, SIG_START)
        if where is None:
            raise SystemExit("fixed: no room for %s (%d bytes)" % (name, len(blob)))
        fixed.place(where, blob, name)
        eq[name] = where
    tables = ["DLA_BASE:"] + by(list(dls[:ROWS * 10])) + ["DLB_BASE:"] + by(list(dls[ROWS * 10:]))

    # each piece after a ";;; FAR" line goes in a free gap of its own:
    # assembled once to learn its size, placed, and its labels handed to the
    # main block as equates
    # the scene-page section: assembled at the scene pages' free $9420 and
    # placed in all of them; its labels reach the main block as equates
    sp_a = src.index("\n;;; SCENEPAGE")
    sp_b = src.index("\n;;; END SCENEPAGE")
    sp_text = src[sp_a:sp_b].split("\n", 2)[2].splitlines()     # past the marker line
    src = src[:sp_a] + "\n" + src[sp_b:].split("\n", 2)[2]
    # the level-1 section: only in the scene pages that call it (scenes 1
    # and 6), at a run free in both; its labels reach the scene page
    l1_a = src.index("\n;;; LEVEL1PAGE")
    l1_b = src.index("\n;;; END LEVEL1PAGE")
    l1_parts = [[ln for ln in part.splitlines() if not ln.startswith(";;;")]
                for part in src[l1_a:l1_b].split("\n", 2)[2].split("\n;;; PART")]
    l1_parts = l1_parts[:1] + [p[1:] for p in l1_parts[1:]]     # past each ";;; PART" line
    src = src[:l1_a] + "\n" + src[l1_b:].split("\n", 2)[2]
    # the fast fill's code: assembled at its cart-RAM address, its image in
    # the art bank, copied at load (CopyFill)
    rf_a = src.index("\n;;; RAMFILL")
    rf_b = src.index("\n;;; END RAMFILL")
    rf_text = [ln for ln in src[rf_a:rf_b].splitlines()[1:] if not ln.startswith(";;;")]
    src = src[:rf_a] + "\n" + src[rf_b:].split("\n", 2)[2]
    pieces = src.split("\n;;; FAR")
    src = pieces[0]

    def assemble_at(lines_in, org, extra_eq):
        lines = ["%s = $%04X" % (k, v) for k, v in sorted(eq.items())] + \
                ["%s = $%04X" % (k, v) for k, v in sorted(extra_eq.items())] + \
                ["    .org $%04X" % org] + lines_in
        a = asm.Assembler()
        return a.assemble(lines), a.sym
    rf_code, rf_sym = assemble_at(rf_text, K.RAMFILL_TABLE, {})
    if K.RAMFILL_TABLE + len(rf_code) > 0x7300:
        raise SystemExit("the fast fill's code (%d bytes) runs into the engine at $7300" % len(rf_code))
    for i, name in enumerate(K.RAMFILL_ENTRIES):
        if rf_sym[name] != K.RAMFILL_TABLE + 3 * i:
            raise SystemExit("fast fill jump table: %s at $%04X" % (name, rf_sym[name]))
    if rf_sym["FpPatch0"] >> 8 != rf_sym["FpPatched"] >> 8:
        raise SystemExit("fast fill: the patch code crosses a page (its table holds low bytes)")
    rf_img = art.find(len(rf_code), 0x8000, 0xC000)
    if rf_img is None:
        raise SystemExit("art bank: no room for the fast fill's image (%d bytes)" % len(rf_code))
    art.place(rf_img, rf_code, "fast fill image")
    eq.update({"IMG_RAMFILL": rf_img, "LEN_RAMFILL": len(rf_code)})
    print("fast fill code $%04X + %d bytes (cart RAM), image in the art bank at $%04X" % (
        K.RAMFILL_TABLE, len(rf_code), rf_img))
    # Two passes, so a far piece may call into the main block and the other
    # way round: the main block first with its far labels at a placeholder
    # (every reference between them is an absolute address above $E000, so
    # no instruction changes size), then each piece against the main block's
    # labels, placed; then the main block again with the pieces' real
    # addresses. The largest pieces are placed first.
    texts = [p.split("\n", 1)[1].splitlines() for p in pieces[1:]]   # past the marker line
    label = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")
    far_names = {m.group(1) for t in texts for ln in t for m in [label.match(ln)] if m}
    sp_names = {m.group(1) for ln in sp_text for m in [label.match(ln)] if m}
    main_lines = src.splitlines() + tables
    _, main_sym = assemble_at(main_lines, K.SYS_TABLE, {n: 0xF500 for n in far_names | sp_names})
    main_eq = {k: v for k, v in main_sym.items() if k not in eq and k not in far_names and k not in sp_names}
    # the level-1 code in its parts (each in a free run of both pages, the
    # largest first; they call each other only by JSR/JMP, so sizes don't
    # depend on where the others go), then the scene-page code at its fixed
    # address in every scene page
    l1_names = {m.group(1) for part in l1_parts for ln in part for m in [label.match(ln)] if m}
    ph = {n: 0x8000 for n in l1_names}
    sp_size = len(assemble_at(sp_text, K.SCENEPAGE_TABLE, dict(main_eq, **ph))[0])
    sp_end = K.SCENEPAGE_TABLE + sp_size
    l1_banks = [banks[L.SCENE_BANK[sc]] for sc in L.LEVEL1_SCENES]

    def own(k, syms):                        # the other parts' labels only
        mine = {m.group(1) for ln in l1_parts[k] for m in [label.match(ln)] if m}
        return {n: v for n, v in syms.items() if n not in mine}

    def l1_free(a):
        return not (K.SCENEPAGE_TABLE <= a < sp_end) and all(not b.used[a - b.base] for b in l1_banks)
    l1_at = {}
    for k in sorted(range(len(l1_parts)), key=lambda k: -len(assemble_at(l1_parts[k], 0x8000, own(k, ph))[0])):
        size = len(assemble_at(l1_parts[k], 0x8000, own(k, ph))[0])
        at = next((a for a in range(0x8000, 0xC000 - size + 1)
                   if all(l1_free(a + i) for i in range(size))), None)
        if at is None:
            runs, run = [], None
            for a in range(0x8000, 0xC001):
                if a < 0xC000 and l1_free(a):
                    run = a if run is None else run
                elif run is not None:
                    runs.append((a - run, run))
                    run = None
            raise SystemExit("level-1 code part %d (%d bytes): no room in the level-1 scene pages (largest: %s)" % (
                k, size, ", ".join("$%04X+%d" % (r, n) for n, r in sorted(runs, reverse=True)[:4])))
        l1_at[k] = at
        for b in l1_banks:
            b.place(at, bytes(size), "level-1 system code")     # reserved; filled below
    l1_sym = {}
    for k, part in enumerate(l1_parts):
        l1_sym.update({n: v for n, v in assemble_at(part, l1_at[k], own(k, ph))[1].items()
                       if n in l1_names and n not in own(k, ph)})
    for k, part in enumerate(l1_parts):
        code_k = assemble_at(part, l1_at[k], own(k, l1_sym))[0]
        for b in l1_banks:
            b.data[l1_at[k] - b.base:l1_at[k] - b.base + len(code_k)] = code_k
        print("level-1 system code $%04X + %d bytes, in scene pages %s" % (
            l1_at[k], len(code_k), ", ".join(str(sc) for sc in L.LEVEL1_SCENES)))
    sp_code, sp_sym = assemble_at(sp_text, K.SCENEPAGE_TABLE, dict(main_eq, **l1_sym))
    if os.environ.get("SPFREE"):              # the free runs every scene page shares
        sb = [banks[L.SCENE_BANK[sc]] for sc in L.SCENES]
        run = None
        for a in range(0x8000, 0xC000):
            free = all(not b.used[a - b.base] for b in sb)
            if free and run is None:
                run = a
            if (not free or a == 0xBFFF) and run is not None:
                if a - run >= 32:
                    print("scene pages: $%04X-$%04X free in all (%d bytes)" % (run, a - 1, a - run))
                run = None
        print("scene-page code: %d bytes" % len(sp_code))
        run = None
        for a in range(0xC000, SIG_START + 1):
            free = a < SIG_START and not fixed.used[a - fixed.base]
            if free and run is None:
                run = a
            if not free and run is not None:
                if a - run >= 16:
                    print("fixed bank: $%04X-$%04X free (%d bytes)" % (run, a - 1, a - run))
                run = None
    for sc in L.SCENES:
        banks[L.SCENE_BANK[sc]].place(K.SCENEPAGE_TABLE, sp_code, "scene-page system code")
    for i, name in enumerate(K.SCENEPAGE_ENTRIES):
        if sp_sym[name] != K.SCENEPAGE_TABLE + 3 * i:
            raise SystemExit("scene-page jump table: %s at $%04X" % (name, sp_sym[name]))
    print("scene-page system code $%04X + %d bytes, in every scene page" % (K.SCENEPAGE_TABLE, len(sp_code)))
    sized = [(len(assemble_at(t, 0xF500, main_eq)[0]), t) for t in texts]
    far_eq = {k: v for k, v in sp_sym.items() if k in sp_names}     # the scene page's labels too
    far_sym = dict(far_eq)
    far_sym.update(l1_sym)                     # for the symbol file (the probes)
    far_sym.update({k: v for k, v in rf_sym.items() if 0x7203 <= v < 0x7300 and k not in eq})   # the fast fill's labels
    for size, text in sorted(sized, key=lambda st: -st[0]):
        at = fixed.find(size, 0xF500, SIG_START)
        if at is None:
            raise SystemExit("fixed: no room for a far piece (%d bytes)" % size)
        code_p, sym_p = assemble_at(text, at, main_eq)
        fixed.place(at, code_p, "far system code")
        new = {k: v for k, v in sym_p.items() if k in far_names}
        far_eq.update(new)
        far_sym.update(new)
        print("far system code $%04X + %d bytes (%s)" % (at, len(code_p), ", ".join(sorted(new))))

    def assemble(extra_eq):
        return assemble_at(main_lines, K.SYS_TABLE, dict(far_eq, **extra_eq))
    code, sym = assemble({})
    if {k: v for k, v in sym.items() if k in main_eq} != main_eq:
        raise SystemExit("system code: the main block moved between passes")
    sym.update(far_sym)
    for name, addr in K.sys_symbols().items():
        if sym[name] != addr:
            raise SystemExit("system jump table: %s at $%04X, the game expects $%04X" % (name, sym[name], addr))
    print("system block $%04X + %d bytes = ends $%04X" % (K.SYS_TABLE, len(code), K.SYS_TABLE + len(code) - 1))
    fixed.place(K.SYS_TABLE, code, "system code and tables")
    # the zero-page map (XEGS byte -> 7800 address), for the probes
    with open(os.path.join(HERE, "..", "work", "karateka7800.zp"), "w") as f:
        for z in range(0x100):
            f.write("%02X %04X\n" % (z, zp[z]))
    # the system symbols, for the probes
    with open(os.path.join(HERE, "..", "work", "karateka7800.sym"), "w") as f:
        # and game addresses the probes key on (bank 15 is shared, so any
        # scene's resolver will do): K_B60F, the flip and frame wait in play
        keys = {"K_B60F": link["scenes"][1]["resolver"].new_addr(0xB60F)}
        for name, addr in sorted(list(sym.items()) + list(keys.items()), key=lambda kv: kv[1]):
            f.write("%04X %s\n" % (addr, name))
    # the game instructions the patch kit's options edit (port/mkkit.py), at
    # their 7800 addresses: {name: [[bank, address], ...]}, one per scene bank.
    # Labels, not the addresses inside routines: bank 15 is reassembled, and
    # only labels map exactly (an address inside a routine gets the region's
    # plain offset, which is wrong wherever instructions changed length)
    sites = {}
    for name, xe, delta, scenes in PATCH_SITES:
        sites[name] = [[L.SCENE_BANK[s] if xe < 0xA000 or xe >= 0xC000 else 7,
                        link["scenes"][s]["resolver"].new_addr(xe) + delta] for s in scenes]
    with open(os.path.join(HERE, "..", "work", "karateka7800.sites.json"), "w") as f:
        json.dump(sites, f, indent=1)
    vec = bytes([sym["Nmi"] & 0xFF, sym["Nmi"] >> 8, sym["Reset"] & 0xFF, sym["Reset"] >> 8,
                 sym["Irq"] & 0xFF, sym["Irq"] >> 8])
    fixed.place(0xFFF8, bytes([0xFF, 0xC7]), "region, hash start")
    fixed.place(0xFFFA, vec, "vectors")

    rom = b"".join(bytes(banks[b].data) for b in range(7)) + bytes(fixed.data)
    rom = sign7800.signed(rom)
    hdr = bytearray(128)
    hdr[0] = 3
    hdr[1:10] = b"ATARI7800"
    hdr[17:17 + 22] = b"Karateka (XEGS port)".ljust(22, b"\0")
    hdr[49:53] = len(rom).to_bytes(4, "big")
    hdr[53:55] = (0x0006).to_bytes(2, "big")
    hdr[55] = hdr[56] = 1
    hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
    with open(out_path, "wb") as f:
        f.write(bytes(hdr) + rom)
    used = lambda img: sum(img.used)
    print("fixed bank: %d of %d bytes used; system code $%04X-$%04X; DLs $%04X-$%04X"
          % (used(fixed), BANK, K.SYS_TABLE, K.SYS_TABLE + len(code) - 1, sym["DLA_BASE"], sym["DLA_BASE"] + len(dls) - 1))
    for b in range(7):
        print("bank %d: %d bytes used" % (b, used(banks[b])))
    print("wrote %s (%d bytes)" % (out_path, len(hdr) + len(rom)))
    return sym


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "..", "work", "karateka7800.a78"))
    ap.add_argument("--snd-offset", type=int, default=None,
                    help="the TIA music's transposition in cents (default SND_OFFSET)")
    args = ap.parse_args()
    global SND_OFFSET
    if args.snd_offset is not None:
        SND_OFFSET = args.snd_offset
    try:
        build(args.out)
    except K.LinkError as e:
        raise SystemExit("link error: %s" % e)


if __name__ == "__main__":
    main()
