#!/usr/bin/env python3
"""
Assemble XEGS Karateka's pieces at their 7800 addresses (port/layout7800.py).

For each scene the source generator's analysis (xesource.analyse) is emitted
region by region with every symbol resolved to its 7800 address, the
replacements from the layout applied, and relocated high bytes computed from
each pointer's target. Checks, all fatal:

  - outside bank 15 every chunk assembles to exactly its original size, and
    every label lands at the address the layout says;
  - the shared chunks (bank 15, the engine, the art, the small-sprite block)
    assemble identically for every scene, apart from the engine's seven
    per-scene bytes at $24A5-$24AB;
  - every symbol resolves.

    python port/link7800.py            (checks, prints the chunk table)
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xesource as X          # noqa: E402
import layout7800 as L        # noqa: E402
import asm                    # noqa: E402  (the toolkit's, via xesource's path)

CAR = os.path.join(HERE, "..", "..", "karateka", "Karateka.car")
ROOT = os.path.join(HERE, "..", "work", "analysis")
SYS_ENTRIES = ["SysZpSwap", "SysZpClear", "SysLoadCommon", "SysLoadScene", "SysWaitLine200",
               "SysReadStick", "SysBlitBank", "SysBlitDone", "SysSetVBV", "SysOsStub", "SysCommonTail", "SysSound", "SysSetDlist",
               "SysRowBase", "SysDliExit", "SysStClr"]
SYS_TABLE = 0xE0DA            # a jump table, so the game can be linked before the system
                              # (just after bank 15, which ends at $E221)


# the system code in every scene page (at $9420, free in all six): a jump
# table the game is linked against, like SYS_ENTRIES
SCENEPAGE_ENTRIES = ["ScStClear", "ScStPlayer", "ScStFoe", "ScStFlipL", "ScStCopy",
                     "ScColA", "ScCol68"]
SCENEPAGE_TABLE = 0x9420


# the fast fill's code in cart RAM ($7203-$72FF, free between the engine's
# two parts; copied there at load): its jump table
RAMFILL_ENTRIES = ["RfPass", "RfPattern"]
RAMFILL_TABLE = 0x7203


def sys_symbols():
    out = {n: SYS_TABLE + 3 * i for i, n in enumerate(SYS_ENTRIES)}
    out.update({n: RAMFILL_TABLE + 3 * i for i, n in enumerate(RAMFILL_ENTRIES)})
    out.update({n: SCENEPAGE_TABLE + 3 * i for i, n in enumerate(SCENEPAGE_ENTRIES)})
    return out


class LinkError(Exception):
    pass


def zp_usage(models):
    use = {}
    for m in models.values():
        for name, a in m.symbols.items():
            if name.startswith("Z_"):
                use[a] = use.get(a, 0) + len(m.refs.get(a, ()))
    return use


class Resolver(object):
    def __init__(self, scene, model, zpmap, bank15=None):
        self.s, self.m, self.zp = scene, model, zpmap
        self.sv = L.sysvars()
        self.hw = L.hw_map(self.sv)
        self.sys = sys_symbols()
        self.bank15 = bank15 or {}
        self.carve = list(L.CARVE_COMMON) + list(L.CARVE_SDATA.get(scene, []))
        self.copies = [(lo, hi, d) for lo, hi, d, sc in L.SPRITE_COPIES + L.ART_COPIES if scene in sc]

    def new_addr(self, a):
        for hi, lo, n, at in L.SCENE_TABLES:
            if hi <= a < hi + n:
                return at + (a - hi)          # the scene page's own copy
        if a < 0x100:
            return self.zp[a]
        if a < 0x200:
            return a
        for lo, hi, ram in self.carve:
            if lo <= a < hi:
                return ram + (a - lo)
        for lo, hi, d in self.copies:
            if lo <= a < hi:
                return a + d
        for name, lo, hi, new, where in L.REGIONS:
            if lo <= a < hi:
                if name == "bank15":
                    key = "L_%04X" % a
                    if key in self.bank15:
                        return self.bank15[key]
                    return a - lo + new          # before bank 15 is assembled
                return a - lo + new
        raise LinkError("scene %d: no 7800 home for $%04X" % (self.s, a))

    def resolve(self, name, a):
        if name.startswith("L_"):
            return self.new_addr(a)
        if name.startswith("Z_"):
            return self.zp[a]
        if name in self.hw:
            return self.hw[name]
        if name == "OS_E45C":
            return self.sys["SysSetVBV"]
        if name.startswith("OS_"):
            # never executed in any recorded run: JSR $F946 (scene 0, the
            # middle of an OS screen-editor loop) and LDX $FEA8 (scene 3, data
            # misread as code). A system entry that just returns.
            return self.sys["SysOsStub"]
        if name.startswith("V_") and 0x3000 <= a < 0x6000:
            return self.new_addr(a)
        if name.startswith("HW_"):
            return self.sv["S_SINK"]
        if name.startswith("V_") and 0x0200 <= a < 0x0480:
            # OS page bytes outside the map: only in code no run executed
            # (scene 3's ROL $0278 is data misread as code)
            return self.sv["S_SINK"]
        raise LinkError("scene %d: no 7800 value for %s ($%04X)" % (self.s, name, a))

    def reloc_value(self, loc):
        kind, v, reg, t = self.m.reloc[loc]
        if t >= 0xC000:
            return v          # into the XEGS OS: the disabled checksums, the $25C0 bug
        nt = self.new_addr(t)
        if shared_location(loc):
            # a pointer stored in a shared chunk (bank 15's tables at $B827 and
            # $BE6E) cannot differ by scene; into a scene-code sprite it always
            # means the fixed-bank copy (only runs that reached scenes 2-4 ever
            # used those entries, FINDINGS "The linker")
            for lo, hi, d, sc in L.SPRITE_COPIES:
                if lo <= t < hi:
                    nt = t + d
        return (v + ((nt >> 8) - (t >> 8))) & 0xFF


def shared_location(a):
    return (0xA000 <= a < 0xC000 or 0x1000 <= a < 0x1203 or 0x2300 <= a < 0x3000
            or 0x8000 <= a < 0xA000 or 0x0480 <= a < 0x06E8)


CHUNKS = [   # name, XEGS start, end, keep size, shared
    ("bank15", 0xA000, 0xC000, False, True),
    ("sprites", 0x0480, 0x06E8, True, True),
    ("common", 0x06E8, 0x1000, True, False),
    ("engine1", 0x1000, 0x1203, True, True),
    ("scode", 0x1203, 0x2300, True, False),
    ("engine2", 0x2300, 0x3000, True, True),
    ("sdata", 0x6000, 0x8000, True, False),
    ("art", 0x8000, 0xA000, True, True),
]


def assemble_chunk(res, name, lo, hi, keep):
    m = res.m
    reps = {a: r for a, r in L.replacements(res.s).items() if lo <= a < hi}
    carved = {a for clo, chi, ram in res.carve for a in range(clo, chi)}
    carved |= {a for clo, chi, d in res.copies for a in range(clo, chi)}   # sprites: the copy is the home
    # bank 15's scene-dependent tables: their home is each scene page's copy, so
    # references to them must go through the resolver, not to the chunk's own
    # (dead) bytes
    carved |= {a for hi, lo, n, at in L.SCENE_TABLES for a in range(hi, hi + n)}
    body, local, applied = X.emit_range(m, lo, hi, overrides=reps, keep_size=keep,
                                        reloc_value=res.reloc_value, skip_labels=carved)
    localnames = {m.base_name(a) for a in local}
    eq = []
    for nm, a in sorted(m.symbols.items()):
        if nm in localnames:
            continue
        eq.append("%s = $%04X" % (nm, res.resolve(nm, a)))
    for nm, a in sorted(res.sys.items()):
        eq.append("%s = $%04X" % (nm, a))
    for nm, a in sorted(res.hw.items()):   # the port's own names replacements use
        if nm.startswith("ST_") or nm.startswith("FL_"):
            eq.append("%s = $%04X" % (nm, a))
    named = {nm for nm in m.symbols} | localnames
    for z in range(0x100):                 # replacements may name any of them
        if "Z_%02X" % z not in named:
            eq.append("Z_%02X = $%04X" % (z, res.zp[z]))
    org = [new + (lo - rlo) for rn, rlo, rhi, new, where in L.REGIONS if rlo <= lo < rhi][0]
    lines = eq + ["    .org $%04X" % org] + body
    a = asm.Assembler()
    out = a.assemble(lines)
    if keep:
        if len(out) != hi - lo:
            raise LinkError("scene %d: %s assembled to %d bytes, not %d" % (res.s, name, len(out), hi - lo))
        for addr in local:
            want = res.new_addr(addr)
            got = a.sym.get(m.base_name(addr))
            if got != want:
                raise LinkError("scene %d: %s label %s at $%04X, layout says $%04X"
                                % (res.s, name, m.base_name(addr), got or -1, want))
    labels = {m.base_name(addr): a.sym[m.base_name(addr)] for addr in local}
    return out, org, labels, lines


def link(scenes=L.SCENES, verbose=True):
    car = open(CAR, "rb").read()
    ex = glob.glob(os.path.join(ROOT, "census", "*.ex"))
    reloc = os.path.join(ROOT, "reloc.txt")
    models = {s: X.analyse(car, s, ex, reloc) for s in scenes}
    usage = zp_usage(models)
    zpmap = L.zero_page_map(usage)
    result = {"zp": zpmap, "zp_used": {zpmap[z] for z, n in usage.items() if n},
              "scenes": {}, "shared": {}}
    for s in scenes:
        res = Resolver(s, models[s], zpmap)
        out, org, labels, _lines = assemble_chunk(res, "bank15", 0xA000, 0xC000, False)
        res.bank15 = labels
        chunks = {"bank15": (org, out)}
        for name, lo, hi, keep, shared in CHUNKS[1:]:
            b, org, _l, _lines = assemble_chunk(res, name, lo, hi, keep)
            chunks[name] = (org, b)
        result["scenes"][s] = {"chunks": chunks, "resolver": res}
    # shared chunks must agree across scenes
    for name, lo, hi, keep, shared in CHUNKS:
        if not shared:
            continue
        ref = None
        for s in scenes:
            org, b = result["scenes"][s]["chunks"][name]
            b = bytearray(b)
            if name == "engine2":
                for i in range(0x24A5 - 0x2300, 0x24AC - 0x2300):
                    b[i] = 0                     # the per-scene bytes
            if ref is None:
                ref = (s, org, bytes(b))
            elif (org, bytes(b)) != ref[1:]:
                diff = [i for i in range(min(len(b), len(ref[2]))) if b[i] != ref[2][i]]
                raise LinkError("shared chunk %s differs between scenes %d and %d (%d bytes, first at $%04X)"
                                % (name, ref[0], s, len(diff) or abs(len(b) - len(ref[2])),
                                   org + (diff[0] if diff else 0)))
        result["shared"][name] = result["scenes"][scenes[0]]["chunks"][name]
    if verbose:
        for name, lo, hi, keep, shared in CHUNKS:
            org, b = result["scenes"][scenes[0]]["chunks"][name]
            print("%-8s $%04X-$%04X -> $%04X-$%04X  %5d bytes  %s" % (
                name, lo, hi - 1, org, org + len(b) - 1, len(b), "shared" if shared else "per scene"))
        print("zero page: %d XEGS bytes moved to absolute RAM, $00-$3F placed at %s" % (
            len(L.MOVERS), " ".join("%02X>%02X" % (z, zpmap[z]) for z in range(0x40) if zpmap[z] < 0x100)))
    return result


if __name__ == "__main__":
    try:
        link()
    except LinkError as e:
        raise SystemExit("link error: %s" % e)
