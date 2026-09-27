"""Where a scene holds scene 1's original bytes, its built bank should hold
scene 1's built bytes: list the places it doesn't (a relocation or a
zero-page remap the scene lacks). Scene pages only (scene code, scene data).

    python probes/twindiff.py 6 [0]"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "port"))
import dis as D                  # noqa: E402
import layout7800 as L           # noqa: E402

rom = open(os.path.join(os.path.dirname(__file__), "..", "work", "karateka7800.a78"), "rb").read()[128:]
m1 = D.memory(1)
b1 = rom[L.SCENE_BANK[1] * 0x4000:][:0x4000]


def xe_of(port):
    if port >= 0xA000:
        return port - 0x4000
    if 0x8203 <= port < 0x9300:
        return port - 0x7000
    return None


for s in [int(a) for a in sys.argv[1:]] or [6]:
    ms = D.memory(s)
    bs = rom[L.SCENE_BANK[s] * 0x4000:][:0x4000]
    diffs = []
    for off in range(0x4000):
        x = xe_of(0x8000 + off)
        if x is None or ms.get(x) != m1.get(x):
            continue
        if bs[off] != b1[off]:
            diffs.append((x, b1[off], bs[off]))
    runs = []
    for x, _, _ in diffs:
        if runs and x - runs[-1][1] <= 8:
            runs[-1][1] = x
        else:
            runs.append([x, x])
    print("scene %d: %d bytes differ from scene 1's build where the originals agree, in %d stretches"
          % (s, len(diffs), len(runs)))
    for a, b in runs[:25]:
        print("   $%04X-$%04X" % (a, b))
