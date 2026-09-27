"""Every JSR/JMP to an address in one scene's memory, with the code before it.

    python probes/callers.py SCENE ADDR [BEFORE]     (hex; BEFORE bytes, default 24)
A byte scan: read each hit (the bytes before a call may start mid-instruction)."""
import os
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "port"))
import dis as D  # noqa: E402


def main():
    scene, target = int(sys.argv[1]), int(sys.argv[2], 16)
    before = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x18
    m = D.memory(scene)
    hits = [a for a in sorted(m) if m.get(a) in (0x20, 0x4C) and m.get(a + 1) == target & 0xFF
            and m.get(a + 2) == target >> 8]
    print("scene %d: %d call(s) of $%04X: %s" % (scene, len(hits), target, " ".join("$%04X" % a for a in hits)))
    for a in hits:
        rng = "%04X-%04X" % (max(a - before, 0), a + 3)
        out = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "..", "port", "dis.py"),
                              str(scene), rng], capture_output=True, text=True).stdout
        print(out)


if __name__ == "__main__":
    main()
