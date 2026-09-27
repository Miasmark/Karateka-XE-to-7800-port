import sys, struct, zlib

def png_decode(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not png"
    pos = 8
    idat = b""
    w = h = bitd = ctype = None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos+4])
        tag = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if tag == b"IHDR":
            w, h, bitd, ctype = struct.unpack(">IIBB", chunk[:10])
        elif tag == b"IDAT":
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = 4 if ctype == 6 else 3
    stride = w * ch
    out = bytearray()
    prev = bytearray(stride)
    row = 0
    p = 0
    while p < len(raw):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if f == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 255
        elif f == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                b = prev[i]
                c = prev[i-ch] if i >= ch else 0
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        out += line
        row += 1
    return w, h, out

def to_ascii(w, h, px, ch=3, cols=96, rows=36, thr=80):
    cw = w // cols
    chh = h // rows
    if cw < 1: cw = 1
    if chh < 1: chh = 1
    ramp = " .:-=+*#%@"
    lines = []
    for r in range(rows):
        s = ""
        for c in range(cols):
            tot = 0; n = 0
            for y in range(r*chh, min((r+1)*chh, h), max(1, chh//2)):
                for x in range(c*cw, min((c+1)*cw, w), max(1, cw//2)):
                    o = (y*w + x) * ch
                    v = (px[o] + px[o+1] + px[o+2]) // 3
                    tot += v; n += 1
            s += ramp[min(9, (tot//n) * 10 // 255)]
        lines.append(s)
    return "\n".join(lines)

for p in sys.argv[1:]:
    try:
        w, h, px = png_decode(p)
        print(f"=== {p}  {w}x{h} ===")
        print(to_ascii(w, h, px))
    except Exception as e:
        print(p, "ERR", e)