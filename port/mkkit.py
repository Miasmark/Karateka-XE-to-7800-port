#!/usr/bin/env python3
"""Build the patch kit: everything needed to make the port from the XEGS
cartridge without MAME, an assembler or this project.

    python port/build7800.py          # the port, as usual
    python port/mkkit.py              # -> dist/karateka7800-kit/

The kit (port/kit/make.py is its one command) chops the original into the
7800's order, applies a BPS, optionally applies options from an .abp, signs
and adds the header. This script makes its three data files and proves them:

  kit.json                  the original's identity, the chop map, the header
  karateka7800.bps          chopped original -> the port's 128K body
  karateka7800-options.abp  invincible, easy (anchored bundle of patches)

The chop map is found, not written by hand: every 256-byte page of the port
takes the page of the original that it shares the most bytes with, if it
shares enough to be the same material (the layout moves whole pages, so
data and art line up exactly; reassembled code keeps most of its bytes).
The BPS then does the rest with SourceRead where the chopped image already
has the byte, SourceCopy for original material at any other offset (code
that shifted when it was reassembled), TargetCopy for the port's own
repeated tables, and TargetRead for new bytes only.

Checks, each of which fails the run:
  - make.py, run on the original, gives work/karateka7800.a78 byte for byte;
  - every option set applies, re-signs and verifies, and edits only its
    sites (whose bytes are checked against the instructions they must be);
  - the patch carries no run of 8 or more bytes that the original has
    anywhere (so no cartridge data rides along as literals).
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
ATARI = os.path.join(ROOT, "..")
CAR = os.environ.get("KARATEKA_CAR",
                     os.path.join(ROOT, "Karateka.car") if os.path.exists(os.path.join(ROOT, "Karateka.car"))
                     else os.path.join(ATARI, "karateka", "Karateka.car"))
A78 = os.path.join(ROOT, "work", "karateka7800.a78")
SITES = os.path.join(ROOT, "work", "karateka7800.sites.json")
OUT = os.path.join(ROOT, "dist", "karateka7800-kit")
ABP_REPO = os.environ.get("ABP_REPO", os.path.join(ATARI, "Anchored-Bundle-of-Patches"))
TOOLKIT = os.environ.get("A7800_TOOLKIT",
                         os.path.join(ROOT, "a7800-toolkit", "tools")
                         if os.path.isdir(os.path.join(ROOT, "a7800-toolkit", "tools"))
                         else os.path.join(ATARI, "a7800-toolkit", "tools"))
sys.path.insert(0, ABP_REPO)
sys.path.insert(0, TOOLKIT)

try:
    import abp      # noqa: E402  (making the kit only: kitopt.py needs just OPTIONS)
except ImportError:
    abp = None
import bps          # noqa: E402
import sign7800     # noqa: E402

PAGE = 0x100
BLOCK = 32          # the chop map's grain: each block of the port takes one offset
VOTES_MIN = 2       # 8-byte runs a block needs in common with the original
COPY_MIN = 4        # shortest SourceCopy/TargetCopy worth an action
LEAK_RUN = 8        # longest literal run the original may also contain


def bank_addr(off):
    """A body offset as the 7800 sees it: bank 7 is fixed at $C000."""
    b = off // 0x4000
    return "bank %d $%04X" % (b, (0xC000 if b == 7 else 0x8000) + off % 0x4000)


def body_offset(bank, addr):
    return bank * 0x4000 + addr - (0xC000 if bank == 7 else 0x8000)


# ------------------------------------------------------------------- chop
def chop_map(car, port):
    """[(source offset, dest offset, length)]: where the port's material sits
    in the original. Each BLOCK of the port votes for the offsets into the
    original at which its 8-byte runs occur (runs that occur in more than a
    few places, like filler, do not vote); a block takes the offset with the
    most votes, and neighbours with the same offset merge into one piece.
    Not whole pages: the loader copies some of the original to addresses
    that are not page-aligned with where the cartridge holds it (the common
    block is at $A268 in the XEGS cartridge and runs at $06E8)."""
    G = 8
    occ = {}
    for i in range(len(car) - G + 1):
        occ.setdefault(car[i:i + G], []).append(i)
    picks = []
    for blk in range(0, len(port), BLOCK):
        votes = {}
        for i in range(blk, min(blk + BLOCK, len(port) - G + 1)):
            where = occ.get(port[i:i + G], ())
            if 0 < len(where) <= 4 and len(set(port[i:i + G])) > 2:
                for j in where:
                    votes[j - i] = votes.get(j - i, 0) + 1
        delta = max(votes, key=lambda d: (votes[d], -abs(d))) if votes else None
        picks.append(delta if delta is not None and votes[delta] >= VOTES_MIN else None)
    runs = []
    for k, delta in enumerate(picks):
        d = k * BLOCK
        if delta is None:
            continue
        n = min(BLOCK, len(port) - d)
        if runs and runs[-1][1] + runs[-1][2] == d and runs[-1][0] - runs[-1][1] == delta:
            runs[-1][2] += n
        else:
            runs.append([d + delta, d, n])
    return runs


def complete(car, port, runs):
    """Second pass: stretches of the original that the port uses but the
    first pass placed nowhere (an image that starts mid-block, code whose
    blocks have too few unchanged 8-byte runs to vote) go into the chopped
    image's unused space, so the patch can copy them rather than carry them."""
    G = 8
    base = chopped(car, runs, len(port))
    used = bytearray(len(port))
    for s, d, n in runs:
        used[d:d + n] = b"" * n
    have = {base[i:i + G] for i in range(len(base) - G + 1)}
    occ = {}
    for i in range(len(car) - G + 1):
        occ.setdefault(car[i:i + G], []).append(i)
    need = []                                       # [start, end) in the original
    i = 0
    while i < len(port) - G + 1:
        g = port[i:i + G]
        where = occ.get(g, ())
        if g in have or not where or len(set(g)) < 2:
            i += 1
            continue
        best = (0, 0)
        for j in where[:16]:
            a = 0
            while i - a > 0 and j - a > 0 and port[i - a - 1] == car[j - a - 1]:
                a += 1
            b = G
            while i + b < len(port) and j + b < len(car) and port[i + b] == car[j + b]:
                b += 1
            if a + b > best[1] - best[0]:
                best = (j - a, j + b)
        need.append(best)
        i += 1
    # merge the needed stretches, then drop the ones the base already holds
    need.sort()
    merged = []
    for lo, hi in need:
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    free = []                                       # unused stretches of the base
    k = 0
    while k < len(used):
        if used[k]:
            k += 1
            continue
        e = k
        while e < len(used) and not used[e]:
            e += 1
        free.append([k, e])
        k = e
    added = []
    for lo, hi in merged:                           # split across gaps if need be
        while lo < hi:
            f = next((f for f in free if f[1] > f[0]), None)
            if f is None:
                raise SystemExit("mkkit: no room in the chopped image for original $%05X-$%05X"
                                 % (lo, hi - 1))
            n = min(hi - lo, f[1] - f[0])
            added.append([lo, f[0], n])
            f[0] += n
            lo += n
    return added


def chopped(car, runs, size):
    base = bytearray(size)
    for s, d, n in runs:
        base[d:d + n] = car[s:s + n]
    return bytes(base)


# -------------------------------------------------------------------- BPS
def bps_create(source, target, metadata=b""):
    """A beat BPS using all four actions (bps.create only reads in place)."""
    K = COPY_MIN
    sidx, sidx8 = {}, {}
    for i in range(len(source) - K + 1):
        sidx.setdefault(source[i:i + K], []).append(i)
    for i in range(len(source) - 7):
        sidx8.setdefault(source[i:i + 8], []).append(i)
    tidx = {}
    out = bytearray(bps.MAGIC)
    out += bps.encode_number(len(source)) + bps.encode_number(len(target))
    out += bps.encode_number(len(metadata)) + metadata
    src_rel = tgt_rel = 0
    lit = bytearray()
    stats = {"source_read": 0, "source_copy": 0, "target_copy": 0, "target_read": 0}

    def flush():
        if lit:
            out.extend(bps.encode_number(((len(lit) - 1) << 2) | bps.TARGET_READ))
            out.extend(lit)
            stats["target_read"] += len(lit)
            del lit[:]

    def signed(n):
        return bps.encode_number((abs(n) << 1) | (1 if n < 0 else 0))

    def match(a, b, i, j, limit):
        n = 0
        while i + n < limit and j + n < len(a) and a[j + n] == b[i + n]:
            n += 1
        return n

    p, n_t = 0, len(target)
    added = 0                                   # target positions indexed so far
    while p < n_t:
        # index the target written so far (TargetCopy may overlap forward)
        while added + K <= p:
            tidx.setdefault(target[added:added + K], []).append(added)
            added += 1
        same = 0
        while p + same < n_t and p + same < len(source) and source[p + same] == target[p + same]:
            same += 1
        key = target[p:p + K]
        best, kind, at = 0, None, 0
        # long matches through the 8-byte index (every place it occurs), short
        # ones through the 4-byte one (the last few places, for speed)
        cands = sidx8.get(target[p:p + 8], [])[:512] + sidx.get(key, [])[-48:]
        for s in ([src_rel] if 0 <= src_rel < len(source) else []) + cands:
            m = match(source, target, p, s, n_t)
            if m > best:
                best, kind, at = m, bps.SOURCE_COPY, s
        for s in ([tgt_rel] if 0 <= tgt_rel < p else []) + tidx.get(key, [])[-48:]:
            m = 0
            while p + m < n_t and target[s + m] == target[p + m] and s + m < p + m:
                m += 1
            if m > best:
                best, kind, at = m, bps.TARGET_COPY, s
        if same and same >= best:
            flush()
            out += bps.encode_number(((same - 1) << 2) | bps.SOURCE_READ)
            stats["source_read"] += same
            p += same
        elif best >= K:
            flush()
            out += bps.encode_number(((best - 1) << 2) | kind)
            if kind == bps.SOURCE_COPY:
                out += signed(at - src_rel)
                src_rel = at + best
                stats["source_copy"] += best
            else:
                out += signed(at - tgt_rel)
                tgt_rel = at + best
                stats["target_copy"] += best
            p += best
        else:
            lit.append(target[p])
            p += 1
    flush()
    out += zlib.crc32(source).to_bytes(4, "little")
    out += zlib.crc32(target).to_bytes(4, "little")
    out += zlib.crc32(bytes(out)).to_bytes(4, "little")
    return bytes(out), stats


def literals(patch):
    """The TargetRead runs a BPS carries."""
    h = bps.read_header(patch)
    i, runs = h["actions_at"], []
    while i < h["body_end"]:
        n, i = bps.decode_number(patch, i)
        action, length = n & 3, (n >> 2) + 1
        if action == bps.TARGET_READ:
            runs.append(patch[i:i + length])
            i += length
        elif action in (bps.SOURCE_COPY, bps.TARGET_COPY):
            _, i = bps.decode_number(patch, i)
    return runs


def leak_check(patch, car):
    """Literal stretches of LEAK_RUN bytes or more that the original has."""
    grams = {car[i:i + LEAK_RUN] for i in range(len(car) - LEAK_RUN + 1)}
    hits = 0
    for r in literals(patch):
        for i in range(len(r) - LEAK_RUN + 1):
            g = r[i:i + LEAK_RUN]
            if len(set(g)) > 1 and g in grams:
                hits += 1
    return hits


# ---------------------------------------------------------------- options
# (site, bytes the port has there, bytes the option writes). Each site is a
# game instruction located by the build (port/build7800.py, PATCH_SITES), and
# the expected bytes are checked, so a moved or changed site fails here
# rather than producing a cartridge that edits the wrong code.
OPTIONS = [
    {"id": "invincible", "knob": "player",
     "title": "the player cannot lose: hits cost nothing, no instant deaths, "
              "no gate, no falling off the cliff",
     "note": "the four changes of the xe-easy.lua playthrough aid; the title "
             "and attract sequence are left as they are",
     "edits": [
         # DEC $B6 / BNE +4 -> BEQ +6 / BNE +4: Z is always set here (the
         # LDA #$00 before it), so it goes straight to the RTS with A, X and
         # Y exactly as before, and health is never lowered
         ("player-damage", "c6 b6 d0 04", "f0 06 d0 04"),
         # BEQ $B131 (instant death while running or walking) -> NOP NOP, on
         # to the RTS after it
         ("instant-death", "f0 01", "ea ea"),
         # LDA $A7 -> LDA #$00: the gate is never low enough to crush
         ("gate", "a5 a7", "a9 00"),
         # LDA $A2 -> LDA #$00: never counted as driven over the edge
         ("cliff", "a5 a2", "a9 00"),
     ]},
    {"id": "easy", "knob": "foes",
     "title": "one hit finishes any foe",
     "note": "the foe's damage routine stores 0 instead of taking one away",
     "edits": [
         # DEC $B7 -> STA $B7 with A = 0 (the LDA #$00 before it); Z is still
         # set, so it falls into the foe's death as a last hit would
         ("foe-damage", "c6 b7", "85 b7"),
     ]},
    # where a new game starts, for testing a later part of the game: the
    # title's game start writes the scene number ($D0 = 1); these write
    # another. Dying still returns to scene 1, as a failed scripted run does.
    # Scenes 2 and 3 start cleanly this way (the census and the regressions
    # reach them so, on both machines).
    {"id": "start-level2", "knob": "start",
     "title": "a new game starts at level 2 (scene 2, the fortress gate)",
     "note": "for testing; the title and attract sequence are unchanged",
     "edits": [("game-start", "01", "02")]},
    {"id": "start-level3", "knob": "start",
     "title": "a new game starts at level 3 (scene 3)",
     "note": "for testing; the title and attract sequence are unchanged",
     "edits": [("game-start", "01", "03")]},
    # (no start-finale: scene 4 needs what the end of scene 3 hands over --
    # the player's position among it -- and started cold the player stands
    # in the doorway and never moves, on the original too; FINDINGS "The
    # princess room". Start at level 3 and play into it.)
]
# after-checks: the instruction a patched branch must land on
LANDINGS = {"player-damage": (8, 0x60), "instant-death": (2, 0x60)}


def build_options(port, sites):
    sections, files, options = {}, {}, []
    touched = set()
    for opt in OPTIONS:
        patches = {}
        for site, before, after in opt["edits"]:
            before, after = bytes.fromhex(before), bytes.fromhex(after)
            for bank, addr in sites[site]:
                off = body_offset(bank, addr)
                have = port[off:off + len(before)]
                if have != before:
                    raise SystemExit("mkkit: %s at %s holds %s, expected %s"
                                     % (site, bank_addr(off), have.hex(" "), before.hex(" ")))
                if site in LANDINGS:
                    k, op = LANDINGS[site]
                    if port[off + k] != op:
                        raise SystemExit("mkkit: %s at %s: no $%02X at +%d"
                                         % (site, bank_addr(off), op, k))
                sid = "s_%d_%04X" % (bank, addr)
                sections[sid] = {"addr": "0x%05X" % off, "length": len(before),
                                 "crc32": "0x%08X" % abp.crc32(before),
                                 "what": "%s, %s" % (site, bank_addr(off))}
                member = "p/%s.%s.bps" % (opt["id"], sid)
                files[member] = bps.create(before, after)
                patches[sid] = {"bps": member}
                touched.update(range(off, off + len(before)))
        options.append({"id": opt["id"], "title": opt["title"], "knob": opt["knob"],
                        "note": opt["note"], "patches": patches})
    # anchors: varied ground nothing patches -- the art bank, a scene's
    # data, the fixed bank's system code -- clear of the signature block
    anchors = []
    for bank, addr in ((6, 0x8400), (1, 0xA400), (7, 0xE400)):
        off = body_offset(bank, addr)
        assert not touched & set(range(off, off + 256))
        assert len(set(port[off:off + 256])) > 16, bank_addr(off)
        anchors.append({"addr": "0x%05X" % off, "length": 256,
                        "crc32": "0x%08X" % abp.crc32(port[off:off + 256]),
                        "what": bank_addr(off)})
    manifest = {
        "format": abp.FORMAT,
        "name": "Karateka 7800 (XEGS port) options",
        "what": "Playthrough aids for the 7800 port of XEGS Karateka.",
        "target": {"what": "karateka7800.a78 as make.py builds it, or its bare 128K",
                   "body_size": len(port),
                   "body_sha256": hashlib.sha256(port).hexdigest(),
                   "anchors": anchors, "headers": [0, 128], "base": "0x0"},
        "knobs": {"player": "what hurts the player", "foes": "how much a foe can take",
                  "start": "where a new game starts"},
        "sections": sections,
        "options": options,
    }
    return manifest, files


# ------------------------------------------------------------------- main
def main():
    if abp is None:
        raise SystemExit("mkkit: needs Anchored-Bundle-of-Patches (ABP_REPO, else beside the repository)")
    car_raw = io.open(CAR, "rb").read()
    car = car_raw[16:]
    a78 = io.open(A78, "rb").read()
    hdr, port = a78[:128], a78[128:]
    if not sign7800.verify(port):
        raise SystemExit("mkkit: %s is not signed" % A78)
    sites = json.load(io.open(SITES))

    runs = chop_map(car, port)
    extra = complete(car, port, runs)
    print("chop: %d pieces in place, %d more (%d bytes) the patch copies from"
          % (len(runs), len(extra), sum(n for _, _, n in extra)))
    runs = runs + extra
    base = chopped(car, runs, len(port))
    patch, stats = bps_create(base, port, metadata=b"Karateka 7800 (XEGS port)")
    got, _ = bps.apply(base, patch)
    assert got == port
    leaks = leak_check(patch, car)
    print("chop: %d pieces, %d of %d bytes placed from the original"
          % (len(runs), sum(n for _, _, n in runs), len(port)))
    print("bps: %d bytes; source read %d, source copy %d, target copy %d, literal %d"
          % (len(patch), stats["source_read"], stats["source_copy"], stats["target_copy"], stats["target_read"]))
    print("leak check: %d literal runs of %d+ bytes found in the original" % (leaks, LEAK_RUN))
    if leaks:
        raise SystemExit("mkkit: the patch carries original data as literals")

    manifest, files = build_options(port, sites)

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    io.open(os.path.join(OUT, "karateka7800.bps"), "wb").write(patch)
    abp.write_bundle(os.path.join(OUT, "karateka7800-options.abp"), manifest, files)
    kit = {
        "what": "Make the Atari 7800 port of XEGS Karateka: python make.py Karateka.car",
        "original": {"what": "Karateka (XEGS cartridge, 128K), .car sha256 "
                             + hashlib.sha256(car_raw).hexdigest(),
                     "size": len(car), "body_sha256": hashlib.sha256(car).hexdigest()},
        "chop": runs,
        "chop_readable": ["original $%05X-$%05X -> %s" % (s, s + n - 1, bank_addr(d)) for s, d, n in runs],
        "port": {"body_size": len(port), "bps": "karateka7800.bps",
                 "options": "karateka7800-options.abp",
                 "a78_sha256": hashlib.sha256(a78).hexdigest()},
        "header": {"version": hdr[0], "title": hdr[17:49].rstrip(b"\0").decode("latin-1"),
                   "cart_type": "%04X" % int.from_bytes(hdr[53:55], "big"),
                   "controller1": hdr[55], "controller2": hdr[56], "tv": hdr[57]},
    }
    io.open(os.path.join(OUT, "kit.json"), "w", encoding="utf-8").write(json.dumps(kit, indent=1) + "\n")
    shutil.copy(os.path.join(HERE, "kit", "make.py"), OUT)
    for src in (os.path.join(ABP_REPO, "bps.py"), os.path.join(ABP_REPO, "abp.py"),
                os.path.join(TOOLKIT, "sign7800.py")):
        shutil.copy(src, OUT)
    shutil.copy(os.path.join(ABP_REPO, "LICENSE"), os.path.join(OUT, "LICENSE-abp-bps"))

    # prove it: the kit on its own, from a copy, in a clean process
    def run(*args):
        r = subprocess.run([sys.executable, os.path.join(OUT, "make.py"), CAR] + list(args),
                           capture_output=True, text=True, cwd=OUT)
        return r.returncode, r.stdout + r.stderr
    tmp = os.path.join(OUT, "_check.a78")
    rc, log = run("-o", tmp)
    if rc or io.open(tmp, "rb").read() != a78:
        print(log)
        raise SystemExit("mkkit: the kit does not rebuild the port")
    print("kit rebuilds work/karateka7800.a78 byte for byte")
    for sel in ("invincible", "easy", "invincible,easy", "start-level3", "start-level2,invincible"):
        rc, log = run("--with", sel, "-o", tmp)
        if rc:
            print(log)
            raise SystemExit("mkkit: --with %s failed" % sel)
        out = io.open(tmp, "rb").read()
        body = out[128:]
        assert out[:128] == hdr and sign7800.verify(body)
        diff = [i for i in range(len(port)) if body[i] != port[i]]
        sig = range(len(port) - 0x80, len(port) - 0x80 + sign7800.SIGLEN)
        edits = [i for i in diff if i not in sig]
        allowed = set()
        for sid, sec in manifest["sections"].items():
            opts = [o["id"] for o in manifest["options"] if sid in o["patches"]]
            if set(opts) & set(sel.split(",")):
                o = int(sec["addr"], 16)
                allowed.update(range(o, o + sec["length"]))
        stray = [i for i in edits if i not in allowed]
        if stray:
            raise SystemExit("mkkit: --with %s edits outside its sections: %s" % (sel, bank_addr(stray[0])))
        print("--with %-16s %d bytes edited at its sites, re-signed, verifies" % (sel, len(edits)))
    os.remove(tmp)
    print("wrote %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    main()
