#!/usr/bin/env python3
"""
Test cartridge: can MARIA show the XEGS game's own bitmaps, and what does it
cost the CPU?

Input is one frame captured from the original in MAME (xcap.lua): RAM
$0000-$7FFF and the log of DLIST and colour-register writes with the
scanline each happened on. Output is a 128K SuperGame + 16K RAM cartridge
(the Summer Games board, header flags $0006) that

  - copies the captured $3000-$5FFF (both framebuffers) into cartridge RAM
    at $4000-$6FFF, i.e. the XEGS address + $1000;
  - shows the frame through display lists held in ROM: one 1-line zone per
    XEGS scanline, each line two 20-byte 160A objects reading the bitmap row
    where ANTIC read it (ANTIC mode E and MARIA 160A pack pixels the same
    way: four 2-bit pixels, leftmost in bits 7-6, 00 = background);
  - turns the frame's colour changes (made by DLIs on the XEGS) into a
    palette per line;
  - then counts in a loop, so a probe can read how many CPU cycles each frame
    leaves free. --dma-off builds the same cartridge with MARIA's DMA off,
    for the baseline.

    python port/bitmap_testcart.py xcap.ram xcap.log --frame 4000 -o test.a78
"""
import argparse
import os
import re
import sys

TOOLKIT = os.environ.get("A7800_TOOLKIT",
                         os.path.join(os.path.dirname(__file__), "..", "..",
                                      "a7800-toolkit", "tools"))
sys.path.insert(0, TOOLKIT)
import asm        # noqa: E402
import sign7800   # noqa: E402

RAM_SHIFT = 0x1000          # XEGS $3000-$5FFF -> cartridge RAM $4000-$6FFF
FIRST_XE_LINE = 8           # ANTIC starts the display list on scanline 8
DLL_LINES = 243             # NTSC MARIA DLL coverage
PALREG = [(0x21 + 4 * p, 0x22 + 4 * p, 0x23 + 4 * p) for p in range(8)]


def parse_log(path, frame):
    """The DL address and colour state for one frame.

    Writes logged at scanline >= 240 under frame F are the vertical blank
    just before F was drawn; the rest are F's DLIs, in order."""
    base, dl, changes = {}, {}, []
    for line in open(path):
        m = re.match(r"f(\d+) v(\d+) (\w+)=([0-9A-F]{2})", line)
        if not m or int(m.group(1)) != frame:
            continue
        v, reg, val = int(m.group(2)), m.group(3), int(m.group(4), 16)
        if reg in ("DLISTL", "DLISTH"):
            dl[reg] = val
        elif v >= 240:
            base[reg] = val
        else:
            if not changes or changes[-1][0] != v:
                changes.append((v, {}))
            changes[-1][1][reg] = val
    return dl["DLISTH"] << 8 | dl["DLISTL"], base, changes


def walk_antic(ram, at):
    """Every scanline the display list draws: (line, kind, address, dli)."""
    lines, y, pc, addr = [], FIRST_XE_LINE, at, 0
    for _ in range(400):
        ins = ram[pc]
        mode, dli, lms = ins & 0x0F, bool(ins & 0x80), bool(ins & 0x40)
        if mode == 0:                                   # blank lines
            n = ((ins >> 4) & 7) + 1
            for k in range(n):
                lines.append((y, "blank", None, dli and k == n - 1))
                y += 1
            pc += 1
            continue
        if mode == 1:                                   # jump / JVB: done
            break
        if lms:
            addr = ram[pc + 1] | ram[pc + 2] << 8
            pc += 3
        else:
            pc += 1
        if mode == 0x0E:
            lines.append((y, "E", addr, dli))
            y += 1
            addr += 40
        elif mode == 0x08:
            for k in range(8):
                lines.append((y, "8", addr, dli and k == 7))
                y += 1
            addr += 10
        else:
            raise SystemExit("ANTIC mode %X at $%04X: not handled" % (mode, pc))
    return lines


def expand_mode8(row):
    """Ten mode-8 bytes (40 pixels, 4 colour clocks each) as 40 160A bytes."""
    out = bytearray()
    for b in row:
        for sh in (6, 4, 2, 0):
            p = (b >> sh) & 3
            out.append(p * 0x55)
    return bytes(out)


def build(ram, logpath, frame, dma_off=False):
    dl_at, base, changes = parse_log(logpath, frame)
    lines = walk_antic(ram, dl_at)
    # the DLI handler writes after WSYNC, during the line logged as
    # VCOUNT*2 = v; the new colours show from line v+1 (measured: placing
    # the change one line after the DLI line instead was two lines early)
    colsets, line_pal = [], {}

    def pal_of(state):
        key = (state["COLPF0"], state["COLPF1"], state["COLPF2"])
        if key not in colsets:
            colsets.append(key)
        return colsets.index(key)

    state = dict(base)
    starts = [(FIRST_XE_LINE, pal_of(state))]
    for v, regs in changes:
        y = v + 1
        state.update(regs)
        starts.append((y, pal_of(state)))
    if len(colsets) > 8:
        raise SystemExit("%d colour sets: more than MARIA's 8 palettes" % len(colsets))
    for y, _k, _a, _d in lines:
        line_pal[y] = [p for s, p in starts if s <= y][-1]

    src = ["    .org $C000"]
    src += """reset:
    SEI
    CLD
    LDA #$07
    STA $01
    LDA #$7F
    STA $3C
    LDX #$FF
    TXS
    LDA #$00
    STA $8000
    STA $40
    STA $42
    LDA #$80
    STA $41
    LDA #$40
    STA $43
    LDX #48
    LDY #$00
copy:
    LDA ($40),Y
    STA ($42),Y
    INY
    BNE copy
    INC $41
    INC $43
    DEX
    BNE copy""".split("\n")
    src += ["    LDA #$%02X" % base.get("COLBK", 0), "    STA $20"]
    for p, cols in enumerate(colsets):
        for reg, c in zip(PALREG[p], cols):
            src += ["    LDA #$%02X" % c, "    STA $%02X" % reg]
    src += """    LDA #>dll
    STA $2C
    LDA #<dll
    STA $30
    LDA #$00
    STA $50
    STA $51
    STA $52
    LDA #$%02X
    STA $3C
count:
    INC $50
    BNE count
    INC $51
    BNE count
    INC $52
    JMP count
vec_rti:
    RTI""".replace("%02X", "%02X" % (0x60 if dma_off else 0x40)).split("\n")

    # data: one DL per drawn line, a shared empty DL, expanded mode-8 rows
    src.append("dl_empty:")
    src.append("    .byte $00,$00")
    by_line = {y: (k, a) for y, k, a, _d in lines}
    wide = {}
    for y, (k, a) in sorted(by_line.items()):
        if k == "8" and a not in wide:
            wide[a] = "m8_%04X" % a
            src.append(wide[a] + ":")
            src.append("    .byte " + ",".join("$%02X" % b for b in expand_mode8(ram[a:a + 10])))
    for y, (k, a) in sorted(by_line.items()):
        if k == "blank":
            continue
        p = line_pal[y]
        width = (-20) & 0x1F
        src.append("dl_%d:" % y)
        if k == "E":
            left, right = a + RAM_SHIFT, a + RAM_SHIFT + 20
            src.append("    .byte $%02X,$%02X,$%02X,$00" % (left & 0xFF, p << 5 | width, left >> 8))
            src.append("    .byte $%02X,$%02X,$%02X,$50" % (right & 0xFF, p << 5 | width, right >> 8))
        else:
            src.append("    .byte <%s,$%02X,>%s,$00" % (wide[a], p << 5 | width, wide[a]))
            src.append("    .byte <%s+20,$%02X,>%s+20,$50" % (wide[a], p << 5 | width, wide[a]))
        src.append("    .byte $00,$00")
    src.append("dll:")
    for i in range(DLL_LINES):
        y = FIRST_XE_LINE + i
        k = by_line.get(y, ("blank", None))[0]
        target = "dl_empty" if k == "blank" else "dl_%d" % y
        src.append("    .byte $00,>%s,<%s" % (target, target))
    return src, colsets, starts, dl_at, lines


def assemble(src):
    """(bytes, symbol table)."""
    a = asm.Assembler()
    return a.assemble(src), a.sym


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("ram")
    ap.add_argument("log")
    ap.add_argument("--frame", type=int, required=True)
    ap.add_argument("--dma-off", action="store_true")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    ram = open(args.ram, "rb").read()
    src, colsets, starts, dl_at, lines = build(ram, args.log, args.frame, args.dma_off)
    code_lines = [l for l in src if l.strip()]
    # pad to the vectors: signature zone $FF80-$FFF7 left erased
    body, sym = assemble(code_lines)
    if len(body) > 0x3F80:
        raise SystemExit("fixed bank overflows: %d bytes" % len(body))
    fixed = bytearray(body) + b"\xFF" * (0x4000 - len(body))
    fixed[0x3FF8] = 0xFF
    fixed[0x3FF9] = 0xC7
    for v in (0x3FFA, 0x3FFE):                          # NMI, IRQ -> RTI
        at = sym["vec_rti"]
        fixed[v:v + 2] = bytes((at & 0xFF, at >> 8))
    fixed[0x3FFC:0x3FFE] = b"\x00\xC0"                   # RESET -> $C000
    bank0 = bytearray(ram[0x3000:0x6000]) + b"\xFF" * 0x1000
    rom = bytes(bank0) + b"\xFF" * (0x4000 * 6) + bytes(fixed)
    rom = sign7800.signed(rom)
    hdr = bytearray(128)
    hdr[0] = 3
    hdr[1:10] = b"ATARI7800"
    hdr[17:17 + 20] = b"Karateka MARIA test"[:20].ljust(20, b"\0")
    hdr[49:53] = len(rom).to_bytes(4, "big")
    hdr[53:55] = (0x0006).to_bytes(2, "big")            # SuperGame + RAM @ $4000
    hdr[55] = hdr[56] = 1
    hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
    open(args.out, "wb").write(bytes(hdr) + rom)
    drawn = [l for l in lines if l[1] != "blank"]
    print("DL $%04X: %d lines drawn (XEGS lines %d-%d)" % (dl_at, len(drawn), drawn[0][0], drawn[-1][0]))
    print("palettes:", ["%02X/%02X/%02X" % c for c in colsets], "starting at lines", starts)
    print("fixed bank used: %d bytes; wrote %s" % (len(body), args.out))


if __name__ == "__main__":
    main()
