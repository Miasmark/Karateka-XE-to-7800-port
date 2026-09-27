"""Pointer high bytes a scene loads and stores to a pointer's high half ($04
blit source, $E6 text, $15 copy destination) that reloc.txt does not relocate:
LDA/LDX/LDY #imm, or LDA/LDX/LDY table,X/Y (each table entry checked), where
the value falls in a region that moves. A byte scan: read each hit.

    python probes/scanhi.py [scene ...]
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "port"))
import dis as D                       # noqa: E402
from reloclist import REGIONS, SCENE_SPECIFIC   # noqa: E402

MOVES = ("sprites", "common", "engine1", "scode", "engine2", "scode2", "engine3", "sdata")
PTR_HI = {0x04, 0xE6, 0x15}
ROOT = os.path.join(os.path.dirname(__file__), "..", "work", "analysis")


def region(a):
    for n, lo, hi in REGIONS:
        if lo <= a < hi:
            return n
    return "?"


def main():
    scenes = [int(s) for s in sys.argv[1:]] or [0, 1, 2, 3, 4, 6]
    reloc = {}
    for line in open(os.path.join(ROOT, "reloc.txt")):
        if line.startswith("#"):
            continue
        sc, loc = line.split()[:2]
        reloc.setdefault(sc, set()).add(int(loc, 16))
    for s in scenes:
        m = D.memory(s)
        done = reloc.get("*", set()) | reloc.get(str(s), set())
        for a in range(0x1203, 0x8000):
            if region(a) not in SCENE_SPECIFIC and region(a) not in ("common",):
                continue
            op = m.get(a)
            # LDA/LDX/LDY #imm ; STA/STX/STY zp
            if op in (0xA9, 0xA2, 0xA0) and m.get(a + 2) in (0x85, 0x86, 0x84) and m.get(a + 3) in PTR_HI:
                v = m.get(a + 1)
                if region(v << 8) in MOVES and (a + 1) not in done:
                    print("scene %d %04X: LD #$%02X -> $%02X  (%s)" % (s, a, v, m.get(a + 3), region(v << 8)))
            # LDA/LDX/LDY abs,X|Y ; STA zp
            if op in (0xBD, 0xB9, 0xBE, 0xBC) and m.get(a + 3) in (0x85, 0x86, 0x84) and m.get(a + 4) in PTR_HI:
                t = m.get(a + 1) | (m.get(a + 2) << 8)
                bad = []
                for i in range(32):
                    v = m.get(t + i)
                    if v is None:
                        break
                    if region(v << 8) in MOVES and (t + i) not in done:
                        bad.append("%04X=%02X" % (t + i, v))
                if bad:
                    print("scene %d %04X: LD $%04X,idx -> $%02X  unrelocated %d: %s" % (
                        s, a, t, m.get(a + 4), len(bad), " ".join(bad[:12])))


if __name__ == "__main__":
    main()
