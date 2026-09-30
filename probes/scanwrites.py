"""Every instruction in the game's code (all scenes, all chunks, as the
linker emits them) that writes to an XEGS address range LO-HI (hex),
statically: stores and read-modify-writes with an absolute operand (a label
or value in the range, indexed or not). Usage:
    python probes/scanwrites.py 1000 1203
The code is the linker's view (the census's code map), so code no run
reached may be missing or misread."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import xesource as X     # noqa: E402

lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16)
WRITERS = {"STA", "STX", "STY", "INC", "DEC", "ASL", "LSR", "ROL", "ROR"}
car = open(K.CAR, "rb").read()
import glob
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))
reloc = os.path.join(K.ROOT, "reloc.txt")
found = {}
for s in L.SCENES:
    m = X.analyse(car, s, ex, reloc)
    zpmap = L.zero_page_map(K.zp_usage({s: m}))
    res = K.Resolver(s, m, zpmap)
    for name, clo, chi, keep, shared in K.CHUNKS:
        try:
            out, org, labels, lines = K.assemble_chunk(res, name, clo, chi, keep)
        except Exception as e:
            print("scene %d %s: %s" % (s, name, e))
            continue
        pc = None
        for ln in lines:
            # (absolute operands are written "STA.w L_xxxx" where a symbol
            # could shrink into zero page: the .w is optional here)
            mt = re.match(r"\s+([A-Z]{3})(?:\.w)?\s+([LV]_([0-9A-F]{4}))", ln)
            if mt and mt.group(1) in WRITERS:
                a = int(mt.group(3), 16)
                if lo <= a < hi:
                    found.setdefault((mt.group(1), mt.group(2)), set()).add((s, name))
for (op, lab), where in sorted(found.items(), key=lambda kv: kv[0][1]):
    print("%s %s  in %s" % (op, lab, ", ".join("scene %d %s" % w for w in sorted(where))))
print("%d distinct writes" % len(found))
