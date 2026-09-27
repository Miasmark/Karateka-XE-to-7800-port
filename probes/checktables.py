"""Follow pointer tables' entries through the built cartridge the way the
blitter reads (fixed bank; art bank for $80-$9F and page-mapped $A0-$BF;
otherwise the scene's page) and compare each sprite (2-byte header, height
x width) with the original's.

    python probes/checktables.py      (scene 4's finale tables)
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "port"))
import dis as D                  # noqa: E402
import layout7800 as L           # noqa: E402

ROM = os.path.join(os.path.dirname(__file__), "..", "work", "karateka7800.a78")
TABLES = {4: [(0x7DD9, 0x7DDF, 6), (0x7DE5, 0x7DDF, 6), (0x7E00, 0x7E22, 34), (0x7E88, 0x7EA3, 27),
              (0x7EF4, 0x7F0F, 27), (0x7F60, 0x7F82, 34), (0x1D0F, 0x1D34, 37)]}


def main():
    rom = open(ROM, "rb").read()[128:]
    bad = 0
    for scene, tabs in TABLES.items():
        m = D.memory(scene)
        b = L.SCENE_BANK[scene]

        def at(bank, a):
            return rom[bank * 0x4000 + (a - (0xC000 if bank == 7 else 0x8000))]
        pagemap = [at(b, L.SP_PAGEMAP + i) for i in range(32)]

        def blit_read(a):
            hi = a >> 8
            if a >= 0xC000:
                return at(7, a)
            if 0x80 <= hi < 0xA0:
                return at(L.ART_BANK, a)
            if 0xA0 <= hi < 0xC0:
                return at(L.ART_BANK, a) if pagemap[hi - 0xA0] else at(b, a)
            return None

        def table_byte(xe):
            return at(b, xe + (0x4000 if xe >= 0x6000 else 0x7000))
        good = skipped = 0
        for lo, hi, n in tabs:
            for i in range(n):
                xe = m[hi + i] * 256 + m[lo + i]
                h, w = m.get(xe, 0), m.get(xe + 1, 0)
                if xe >= 0x8000 or not h or not w or h * w > 600:
                    skipped += 1                    # art, or not a sprite
                    continue
                p = table_byte(hi + i) * 256 + table_byte(lo + i)
                ok = blit_read(p) is not None and all(blit_read(p + k) == m[xe + k] for k in range(2 + h * w))
                if ok:
                    good += 1
                else:
                    bad += 1
                    print("scene %d: table $%04X[%d]: $%04X reads wrong at $%04X" % (scene, hi, i, xe, p))
        print("scene %d: %d sprites read identically, %d wrong, %d skipped (art or not a sprite)"
              % (scene, good, bad, skipped))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
