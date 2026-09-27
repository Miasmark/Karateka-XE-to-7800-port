#!/usr/bin/env python3
"""Disassemble ranges of one XEGS Karateka scene's address space.

    python port/dis.py SCENE START-END [START-END ...]      (hex ranges)
Scene selects the code bank at $1000 and the data bank at $6000; common is at
$0480, art (bank 14) at $8000, bank 15 at $A000."""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("A7800_TOOLKIT", os.path.join(HERE, "..", "..", "a7800-toolkit", "tools")))
import m6502  # noqa: E402

CAR = os.environ.get("KARATEKA_CAR", os.path.join(HERE, "..", "..", "karateka", "Karateka.car"))
CODE = {0: 13, 1: 7, 2: 1, 3: 5, 4: 3, 5: 13, 6: 9}
DATA = {0: 11, 1: 8, 2: 2, 3: 6, 4: 4, 5: 11, 6: 10}


def memory(scene):
    car = open(CAR, "rb").read()[16:]
    bank = lambda n: car[n * 0x2000:(n + 1) * 0x2000]
    m = {}
    for i, b in enumerate(bank(12)[:0xB80]):
        m[0x0480 + i] = b
    for start, data in ((0x1000, bank(CODE[scene])), (0x6000, bank(DATA[scene])),
                        (0x8000, bank(14)), (0xA000, bank(15))):
        for i, b in enumerate(data):
            m[start + i] = b
    return m


def line(m, pc):
    op = m.get(pc, 0)
    mn, mode, _ill = m6502.OPCODES[op]
    n = 1 + m6502.MODES[mode]
    b = [m.get(pc + k, 0) for k in range(n)]
    if n == 1:
        arg = ""
    elif mode == "imm":
        arg = "#$%02X" % b[1]
    elif mode == "rel":
        arg = "$%04X" % ((pc + 2 + ((b[1] ^ 0x80) - 0x80)) & 0xFFFF)
    elif n == 2:
        arg = {"zp": "$%02X", "zpx": "$%02X,X", "zpy": "$%02X,Y", "izx": "($%02X,X)", "izy": "($%02X),Y"}[mode] % b[1]
    else:
        arg = {"abs": "$%04X", "abx": "$%04X,X", "aby": "$%04X,Y", "ind": "($%04X)"}[mode] % (b[1] | b[2] << 8)
    return n, "%04X  %-9s %s %s" % (pc, " ".join("%02X" % x for x in b), mn, arg)


def main():
    scene = int(sys.argv[1])
    m = memory(scene)
    for r in sys.argv[2:]:
        a, b = (int(x, 16) for x in r.split("-"))
        print("; ---- scene %d  %s" % (scene, r))
        pc = a
        while pc < b:
            n, t = line(m, pc)
            print(t)
            pc += n


if __name__ == "__main__":
    main()
