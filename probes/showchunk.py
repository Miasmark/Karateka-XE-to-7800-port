"""The linker's assembly for one chunk of one scene, lines whose XEGS
address (the L_xxxx labels) falls in LO-HI (hex), with the lines between:
    python probes/showchunk.py 3 engine2 2AF0 2B70"""
import os
import re
import sys
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "port"))
import link7800 as K     # noqa: E402
import layout7800 as L   # noqa: E402
import xesource as X     # noqa: E402

scene, chunk = int(sys.argv[1]), sys.argv[2]
lo, hi = int(sys.argv[3], 16), int(sys.argv[4], 16)
car = open(K.CAR, "rb").read()
ex = glob.glob(os.path.join(K.ROOT, "census", "*.ex"))
m = X.analyse(car, scene, ex, os.path.join(K.ROOT, "reloc.txt"))
res = K.Resolver(scene, m, L.zero_page_map(K.zp_usage({scene: m})))
for name, clo, chi, keep, shared in K.CHUNKS:
    if name != chunk:
        continue
    out, org, labels, lines = K.assemble_chunk(res, name, clo, chi, keep)
    on = False
    for ln in lines:
        mt = re.match(r"L_([0-9A-F]{4}):", ln)
        if mt:
            on = lo <= int(mt.group(1), 16) < hi
        if on:
            print(ln)
