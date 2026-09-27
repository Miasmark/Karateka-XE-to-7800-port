#!/usr/bin/env python3
"""Walk every tune's data (tune table $25C0, 28 entries -> tune list -> pattern ref ->
note stream with its header pointer) in the XEGS scene image and check each
pointer word against the port's linked engine2 chunk. Prints the pointers
whose 7800 high byte is not relocated.  python probes/tunewalk.py [SCENE]"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import dis as D            # noqa: E402
import link7800 as K       # noqa: E402

scene = int(sys.argv[1]) if len(sys.argv) > 1 else 4
xe = D.memory(scene)
r = K.link(scenes=[scene], verbose=False)
res = r["scenes"][scene]["resolver"]
chunks = r["scenes"][scene]["chunks"]


def port_word(loc):
    for name, lo, hi, keep, shared in K.CHUNKS:
        if lo <= loc < hi and keep:
            b = chunks[name][1]
            return b[loc - lo] | b[loc - lo + 1] << 8
    return None

w = lambda a: xe[a] | xe[a + 1] << 8
ptrs = {}
MUSIC = (0x1203, 0x3000)   # scene code and engine2: where the tune data lives                  # location -> (target, what)


def note(loc, what):
    ptrs[loc] = (w(loc), what)
    return w(loc)


for i in range(28):
    t = note(0x25C0 + 2 * i, "tune %d table" % i)
    k = 0
    while k < 200:
        hi = xe[t + k + 1]
        if hi == 0xFF:
            break
        if hi in (0xFE, 0xFD):
            k += 4
            continue
        p, q = w(t + k), None
        if MUSIC[0] <= p < MUSIC[1]:
            q = w(p)
        if q is None or not MUSIC[0] <= q < MUSIC[1] or not MUSIC[0] <= w(q) < MUSIC[1]:
            print("tune %d list+%d: $%04X -> %s, not music in scene %d" % (i, k, p, q and "$%04X" % q, scene))
            k += 2
            continue
        note(t + k, "tune %d list+%d" % (i, k))
        note(p, "tune %d pattern ref" % i)
        note(q, "tune %d stream header" % i)
        k += 2
bad = 0
for loc in sorted(ptrs):
    t, what = ptrs[loc]
    want = res.new_addr(t) if t < 0xC000 else t
    got = port_word(loc)
    ok = got == want
    bad += not ok
    if not ok or os.environ.get("ALL"):
        print("$%04X %-26s XE $%04X  7800 $%04X  want $%04X %s" % (loc, what, t, got, want, "" if ok else "WRONG"))
print("%d pointers, %d wrong" % (len(ptrs), bad))
