"""Bytes the linker changes inside instructions only the static trace
claims (the census never ran them in that scene): a relocated operand there
is a changed byte of the cartridge, and if the "instruction" is really data
(an image the trace misread) the change damages it. Per scene and chunk:
the instruction, the bytes before and after, and whether the census saw the
scene read those bytes as data (.rd). Usage: python probes/staticonly.py"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import xesource as X     # noqa: E402

car = open(K.CAR, "rb").read()
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))


def reads(scene):
    out = set()
    for p in glob.glob(os.path.join(K.ROOT, "census", "*.rd")):
        for line in open(p):
            k = int(line.split()[0])
            if (k >> 16) & 0xFF == scene:
                out.add(k & 0xFFFF)
    return out


ex_all = X.executed(ex)
# every scene's memory and executed set: a static-only instruction another
# scene ran with the same bytes is that scene's code shared; one it ran with
# other bytes (or no scene ran) is only the trace's word
mems = {s: X.analyse(car, s, ex, os.path.join(K.ROOT, "reloc.txt")).mem for s in L.SCENES}
exs = {s: X.executed(ex, s) for s in L.SCENES}


def elsewhere(s, pc, n):
    same = [t for t in L.SCENES if t != s and pc in exs[t] and
            all(mems[t].get(pc + j) == mems[s].get(pc + j) for j in range(n))]
    other = [t for t in L.SCENES if t != s and pc in exs[t] and t not in same]
    if same:
        return "ran in scene %s, same bytes" % ",".join(map(str, same))
    if other:
        return "ran in scene %s WITH OTHER BYTES" % ",".join(map(str, other))
    return "NEVER RAN"


for s in L.SCENES:
    m = X.analyse(car, s, ex, os.path.join(K.ROOT, "reloc.txt"))
    res = K.Resolver(s, m, L.zero_page_map(K.zp_usage({s: m})))
    ran = X.executed(ex, s) | (X.twin_executed(car, s, m.mem, ex) if s in X.TWIN_OF else set())
    rd = reads(s)
    for name, clo, chi, keep, shared in K.CHUNKS:
        try:
            out, org, labels, lines = K.assemble_chunk(res, name, clo, chi, keep)
        except Exception as e:
            print("scene %d %s: %s" % (s, name, e))
            continue
        if len(out) != chi - clo:
            print("scene %d %s: %d bytes for $%04X-$%04X, not compared" % (s, name, len(out), clo, chi))
            continue
        seen = set()
        for i, b in enumerate(out):
            a = clo + i
            pc = m.owner.get(a)
            if b == m.mem.get(a) or pc is None or pc in ran or pc in seen:
                continue
            seen.add(pc)
            mn, mode, n, opnd = m.insn[pc]
            old = " ".join("%02X" % m.mem[pc + j] for j in range(n))
            new = " ".join("%02X" % out[pc - clo + j] for j in range(n))
            read = any(pc + j in rd for j in range(n))
            print("scene %d %-7s $%04X %s %-4s  %s -> %s  %s%s" % (s, name, pc, mn, mode, old, new,
                  elsewhere(s, pc, n), "; read as data" if read else ""))
