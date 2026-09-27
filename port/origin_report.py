#!/usr/bin/env python3
"""
Which bytes of XEGS Karateka hold addresses, from xorigin.lua's output.

Each input line is  kind pc hi lo n target_min target_max  where hi/lo are
the origins of the address's two halves: the byte a value was first loaded
from, keyed scene*65536+addr in the scene-specific ranges. This groups them
by the high byte's origin and sorts the origins into

  immediate  the operand of an LDA/LDX/LDY #n at an instruction the census
             saw run: becomes #>label / #<label in the source
  table      a byte in the cartridge's code, data, art or bank 15 that is
             not an immediate: an address stored as data
  computed   zero page or RAM with no earlier origin: the address is built
             in place (INC, ADC chains, OS or boot writes), to read by hand

    python port/origin_report.py karateka.car "origin/*.txt" --executed "census2/*.ex"
"""
import argparse
import glob
from collections import defaultdict

IMM_LOADS = {0xA9, 0xA2, 0xA0}          # LDA/LDX/LDY #n
REGIONS = [
    (0x0000, 0x0100, "zero page"), (0x0100, 0x0200, "stack"),
    (0x0200, 0x0480, "RAM $0200-$047F"), (0x0480, 0x1000, "common"),
    (0x1000, 0x1203, "engine"), (0x1203, 0x2300, "scene code"),
    (0x2300, 0x24A5, "engine"), (0x24A5, 0x24AC, "scene code"),
    (0x24AC, 0x3000, "engine"), (0x3000, 0x4800, "framebuffer B"),
    (0x4800, 0x6000, "framebuffer A"), (0x6000, 0x8000, "scene data"),
    (0x8000, 0xA000, "art"), (0xA000, 0xC000, "bank 15"),
    (0xC000, 0x10000, "OS / hardware"),
]


def region(a):
    for lo, hi, name in REGIONS:
        if lo <= a < hi:
            return name
    return "?"


def split(v):
    return (v >> 16, v & 0xFFFF) if v >= 0x10000 else (None, v)


def label(v):
    s, a = split(v)
    return ("s%d:$%04X" % (s, a)) if s is not None else "$%04X" % a


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("car")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--executed", action="append", default=[])
    args = ap.parse_args()

    car = open(args.car, "rb").read()[16:]
    bank = lambda n: car[n * 0x2000:(n + 1) * 0x2000]
    code_bank = {0: 13, 1: 7, 2: 1, 3: 5, 4: 3, 5: 13, 6: 9}
    data_bank = {0: 11, 1: 8, 2: 2, 3: 6, 4: 4, 5: 11, 6: 10}

    def byte_at(scene, a):
        if 0x0480 <= a < 0x1000:
            return bank(12)[a - 0x0480]
        if 0x1000 <= a < 0x3000:
            return bank(code_bank[scene if scene is not None else 1])[a - 0x1000]
        if 0x6000 <= a < 0x8000:
            return bank(data_bank[scene if scene is not None else 1])[a - 0x6000]
        if 0x8000 <= a < 0xA000:
            return bank(14)[a - 0x8000]
        if 0xA000 <= a < 0xC000:
            return bank(15)[a - 0xA000]
        return None

    executed = defaultdict(set)          # scene -> instruction starts
    for g in args.executed:
        for p in glob.glob(g):
            for line in open(p):
                k = int(line.split()[0])
                executed[(k >> 16) & 0xFF].add(k & 0xFFFF)
    ex_any = set().union(*executed.values()) if executed else set()

    def kind_of(v):
        s, a = split(v)
        r = region(a)
        if r in ("zero page", "stack", "RAM $0200-$047F", "framebuffer A", "framebuffer B", "OS / hardware"):
            return "computed"
        op = byte_at(s, a - 1)
        ran = (a - 1) in (executed.get(s, set()) if s is not None else ex_any)
        if op in IMM_LOADS and ran:
            return "immediate"
        return "table"

    by_hi = defaultdict(lambda: {"n": 0, "lo": 0xFFFF, "hi": 0, "kinds": set(), "pcs": set(), "los": set()})
    for pat in args.inputs:
        for p in glob.glob(pat):
            for line in open(p):
                kind, pc, hi, lo, n, tlo, thi = line.split()
                hi, lo, n = int(hi), int(lo), int(n)
                tlo, thi = int(tlo, 16), int(thi, 16)
                e = by_hi[hi]
                e["n"] += n
                e["lo"] = min(e["lo"], tlo)
                e["hi"] = max(e["hi"], thi)
                e["kinds"].add(kind)
                e["pcs"].add(pc)
                e["los"].add(lo)

    groups = defaultdict(list)
    for hi, e in by_hi.items():
        groups[kind_of(hi)].append((hi, e))

    for kind in ("immediate", "table", "computed"):
        rows = sorted(groups.get(kind, []), key=lambda x: (split(x[0])[1], split(x[0])[0] or 0))
        print("== %s: %d high-byte origins" % (kind, len(rows)))
        for hi, e in rows:
            s, a = split(hi)
            targets = region(e["lo"]) if region(e["lo"]) == region(e["hi"]) else "%s .. %s" % (region(e["lo"]), region(e["hi"]))
            lokinds = sorted({kind_of(l) for l in e["los"]})
            print("  hi %-11s (%-12s) -> $%04X-$%04X  %-28s uses %6d  via %s at %s; lo from %s (%d origins)" % (
                label(hi), region(a), e["lo"], e["hi"], targets, e["n"], "/".join(sorted(e["kinds"])),
                " ".join(sorted(e["pcs"])[:6]) + (" ..." if len(e["pcs"]) > 6 else ""),
                "/".join(lokinds), len(e["los"])))


if __name__ == "__main__":
    main()
