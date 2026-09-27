"""Compare framebuffer dumps (probes/fbdump.lua) from the original and the port.

    python port/fbcompare.py work/analysis/fbxe/fb300.bin work/analysis/fb78/fb460.bin [--png out.png]

Each dump is buffer A then buffer B, $17E8 bytes (153 rows of 40). Prints,
per buffer, the rows that differ with the differing byte columns, and
optionally writes a PNG: original, port, and differences (red) side by side,
both buffers, as 2-bit pixels.
"""
import argparse
import struct
import zlib

ROW, ROWS, SIZE = 40, 0x17E8 // 40, 0x17E8


def rows_differing(a, b):
    out = []
    for r in range(ROWS):
        cols = [c for c in range(ROW) if r * ROW + c < SIZE and a[r * ROW + c] != b[r * ROW + c]]
        if cols:
            out.append((r, cols))
    return out


def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb[y * w * 3:(y + 1) * w * 3]) for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("orig")
    ap.add_argument("port")
    ap.add_argument("--png")
    a = ap.parse_args()
    o, p = open(a.orig, "rb").read(), open(a.port, "rb").read()
    shades = [(0, 0, 0), (90, 90, 90), (170, 170, 170), (255, 255, 255)]
    W, H = 160 * 3 + 16, (ROWS + 4) * 2
    img = bytearray(W * H * 3)
    for k, name in enumerate("AB"):
        ob, pb = o[k * SIZE:(k + 1) * SIZE], p[k * SIZE:(k + 1) * SIZE]
        d = rows_differing(ob, pb)
        print("buffer %s: %d of %d rows differ, %d bytes" % (name, len(d), ROWS, sum(len(c) for r, c in d)))
        for r, cols in d[:40]:
            print("  row %3d: cols %s" % (r, " ".join(str(c) for c in cols[:20]) + (" ..." if len(cols) > 20 else "")))
        for i in range(SIZE):
            r, c = divmod(i, ROW)
            y = k * (ROWS + 4) + r
            for px in range(4):
                sh = 6 - 2 * px
                vo, vp = (ob[i] >> sh) & 3, (pb[i] >> sh) & 3
                for panel, col in ((0, shades[vo]), (1, shades[vp]),
                                   (2, (255, 40, 40) if vo != vp else shades[vo // 2])):
                    x = panel * (160 + 8) + c * 4 + px
                    img[(y * W + x) * 3:(y * W + x) * 3 + 3] = bytes(col)
    if a.png:
        png(a.png, W, H, img)
        print("wrote", a.png)


if __name__ == "__main__":
    main()
