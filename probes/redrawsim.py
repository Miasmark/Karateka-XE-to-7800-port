#!/usr/bin/env python3
"""How much drawing a region-by-region redraw would skip, from a draw log
(p7800-blitlog.lua, with sizes): each picture's calls against those of the
picture before last (the one that drew the same buffer). Calls that match
(same call, same parameters, in order) and touch nothing that changed are
skipped; a call is kept if it differs, or touches a changed call's area, or
touches the area of a call kept before it (whatever is drawn over a redrawn
area must be redrawn too). Costs are estimates (cycles).
    python probes/redrawsim.py work/analysis/blogS1/blitlog.log ..."""
import difflib
import re
import sys

ROWS = 153


def parse(path):
    pics, cur, last = [], None, None
    for line in open(path):
        if " flip " in line:
            if cur is not None:
                pics.append(cur)
            cur = []
            continue
        if cur is None:
            continue
        m = re.search(r" size (\d+)x(\d+) col (\d+)", line)
        if m and last is not None:
            last["H"], last["W"], last["C2"] = int(m.group(1)), int(m.group(2)), int(m.group(3))
            continue
        m = re.search(r" blit(\w) \$(\w+) \S+ col (\d+) row (\d+) mode (\w+) shift (\d+) buf (\w+)", line)
        if m:
            last = {"kind": "blit" + m.group(1), "key": m.group(0), "C": int(m.group(3)), "R": int(m.group(4))}
            cur.append(last)
            continue
        m = re.search(r" (fill|pattern) cols (\d+)-(\d+) rows (\d+)-(\d+) buf (\w+)", line)
        if m:
            last = {"kind": m.group(1), "key": m.group(0), "c0": int(m.group(2)), "c1": int(m.group(3)),
                    "r0": int(m.group(4)), "r1": int(m.group(5))}
            cur.append(last)
            continue
        if " clear" in line:
            last = {"kind": "clear", "key": "clear"}
            cur.append(last)
    return pics


def rect(op):
    k = op["kind"]
    if k == "clear":
        return (0, ROWS, 0, 40)
    if k in ("fill", "pattern"):
        return (max(op["r0"] - 35, 0), min(op["r1"] - 35, ROWS), op["c0"], min(op["c1"], 40))
    H, W = op.get("H", 40), op.get("W", 40)
    C = op["C"] - 256 if op["C"] > 127 else op["C"]
    r0 = (op["R"] - 35) & 0xFF
    if r0 >= ROWS:
        return (0, 0, 0, 0)
    if k == "blitA":
        c0, c1 = C, C + W + 1
    else:                                    # mirrored: generous either side
        C2 = op.get("C2", op["C"])
        C2 = C2 - 256 if C2 > 127 else C2
        c0, c1 = min(C, C2) - W - 1, max(C, C2) + W + 2
    return (r0, min(r0 + H, ROWS), max(c0, 0), min(c1, 40))


def meets(a, b):
    return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


def cost(op):
    r0, r1, c0, c1 = rect(op)
    area = max(r1 - r0, 0) * max(c1 - c0, 0)
    if op["kind"] in ("fill", "pattern"):
        return 250 + (r1 - r0) * 35 + 5 * area
    if op["kind"] == "clear":
        return 90000
    return 700 + 45 * area


def main():
    for path in sys.argv[1:]:
        pics = parse(path)
        tot = kept = 0
        for i in range(2, len(pics)):
            a, b = pics[i], pics[i - 2]
            if not a:
                continue
            sm = difflib.SequenceMatcher(a=[o["key"] for o in b], b=[o["key"] for o in a], autojunk=False)
            matched = set()
            for blk in sm.get_matching_blocks():
                matched.update(range(blk.b, blk.b + blk.size))
            mb = set()
            for blk in sm.get_matching_blocks():
                mb.update(range(blk.a, blk.a + blk.size))
            D = [rect(o) for j, o in enumerate(a) if j not in matched] + \
                [rect(o) for j, o in enumerate(b) if j not in mb]
            done = []
            for j, o in enumerate(a):
                r = rect(o)
                c = cost(o)
                tot += c
                if j not in matched or any(meets(r, d) for d in D) or any(meets(r, e) for e in done):
                    kept += c
                    done.append(r)
        print("%s: %d pictures, drawing kept %.0f%% (skipped %.0f%%)" % (
            path, len(pics), 100.0 * kept / max(tot, 1), 100.0 - 100.0 * kept / max(tot, 1)))


if __name__ == "__main__":
    main()
