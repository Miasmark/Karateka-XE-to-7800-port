"""Code the static trace reached only by falling through a branch that always
branches (LDA/LDX/LDY #n right before it fixes the flag: BPL after a load of
0-$7F, BNE after a non-zero load, ...), with no jump or branch to it, and
never run in that scene: most likely data (an image after a routine's end),
which relocating an "operand" would damage. Per scene: the run of such
instructions and the bytes the linker changes in it.
Usage: python probes/deadfall.py"""
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
TAKEN = {"BPL": lambda v: v < 0x80, "BMI": lambda v: v >= 0x80,
         "BNE": lambda v: v != 0, "BEQ": lambda v: v == 0}
STOP = {"RTS", "RTI", "JMP", "BRK"}
for s in L.SCENES:
    m = X.analyse(car, s, ex, os.path.join(K.ROOT, "reloc.txt"))
    ran = X.executed(ex, s) | (X.twin_executed(car, s, m.mem, ex) if s in X.TWIN_OF else set())
    ends = {pc + v[2]: pc for pc, v in m.insn.items()}      # next address -> instruction
    starts = []
    for pc, (mn, mode, n, opnd) in m.insn.items():
        if mn not in TAKEN or pc + n in ran or pc + n not in m.insn or m.refs.get(pc + n):
            continue
        prev = ends.get(pc)
        if prev is None:
            continue
        pmn, pmode, _pn, pop = m.insn[prev]
        if pmn in ("LDA", "LDX", "LDY") and pmode == "imm" and TAKEN[mn](pop):
            starts.append(pc + n)
    chunks = {}
    for name, clo, chi, keep, shared in K.CHUNKS:
        if any(clo <= a < chi for a in starts):
            out, org, labels, lines = K.assemble_chunk(K.Resolver(s, m, L.zero_page_map(K.zp_usage({s: m}))),
                                                      name, clo, chi, keep)
            chunks[name] = (clo, chi, out)
    for a in sorted(starts):
        run, pc = [], a
        while pc in m.insn and pc not in ran and (pc == a or not m.refs.get(pc)):
            run.append(pc)
            mn = m.insn[pc][0]
            pc += m.insn[pc][2]
            if mn in STOP:
                break
        changed = []
        for name, (clo, chi, out) in chunks.items():
            if clo <= a < chi and len(out) == chi - clo:
                changed = ["$%04X %02X->%02X" % (b, m.mem[b], out[b - clo]) for b in range(a, pc)
                           if out[b - clo] != m.mem[b]]
        print("scene %d $%04X-$%04X: %s%s" % (s, a, pc - 1, " / ".join(
            "%s %s" % (m.insn[p][0], m.insn[p][1]) for p in run[:6]),
            ("   CHANGED " + ", ".join(changed)) if changed else ""))
