#!/usr/bin/env python3
"""Make Karateka for the Atari 7800 from the XEGS cartridge.

    python make.py Karateka.car
    python make.py Karateka.car --with invincible,easy -o karateka-easy.a78
    python make.py --list

Needs Python 3 and nothing else: no emulator, no assembler. Four steps:

  1. Chop.   The XEGS cartridge (a .car, or the same 128K without its
             16-byte header) is checked against the dump this kit was made
             from, cut into pages and put back together in the 7800's order
             (kit.json, "chop"). Pages the port does not take from the
             original start as zeroes.
  2. Patch.  karateka7800.bps turns that into the port. A standard BPS,
             so any BPS patcher (beat, Floating IPS, RomPatcher.js) gives the
             same bytes from the chopped image.
  3. Options, if any, from karateka7800-options.abp (an anchored bundle of
             patches: each option checks only the bytes it edits).
  4. Sign and add the .a78 header. The signature is what an NTSC 7800
             checks before it starts in 7800 mode; without a valid one the
             console starts as a 2600, and no emulator notices.

The kit carries no cartridge data of its own: the chop map is offsets, and
the patch carries the port's code and the bytes it changed.
"""
import argparse
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True      # leave the kit folder as it came

import abp          # noqa: E402
import bps          # noqa: E402
import sign7800     # noqa: E402

KIT = os.path.join(HERE, "kit.json")


class MakeError(Exception):
    pass


def load_kit():
    return json.load(io.open(KIT, encoding="utf-8"))


def original_body(raw, kit):
    """The XEGS cartridge's 128K, from a .car or a bare image, checked."""
    want = kit["original"]
    if len(raw) == want["size"] + 16 and raw[:4] == b"CART":
        raw = raw[16:]
    if len(raw) != want["size"]:
        raise MakeError("expected the %dK XEGS cartridge (%s), got %d bytes"
                        % (want["size"] // 1024, want["what"], len(raw)))
    got = hashlib.sha256(raw).hexdigest()
    if got != want["body_sha256"]:
        raise MakeError("this is not the dump the kit was made from:\n"
                        "  expected sha256 %s (%s)\n  got      %s"
                        % (want["body_sha256"], want["what"], got))
    return raw


def chop(car, kit):
    """Step 1: the original's pages in the 7800's order."""
    size = kit["port"]["body_size"]
    base = bytearray(size)
    for src, dst, length in kit["chop"]:
        base[dst:dst + length] = car[src:src + length]
    return bytes(base)


def header(body, kit):
    h = kit["header"]
    hdr = bytearray(128)
    hdr[0] = h["version"]
    hdr[1:10] = b"ATARI7800"
    title = h["title"].encode("latin-1")[:32]
    hdr[17:17 + len(title)] = title
    hdr[49:53] = len(body).to_bytes(4, "big")
    hdr[53:55] = int(h["cart_type"], 16).to_bytes(2, "big")
    hdr[55] = h["controller1"]
    hdr[56] = h["controller2"]
    hdr[57] = h["tv"]
    hdr[100:128] = b"ACTUAL CART DATA STARTS HERE"
    return bytes(hdr)


def make(car_path, wanted=(), report=print):
    kit = load_kit()
    car = original_body(io.open(car_path, "rb").read(), kit)
    report("  original  %s: the dump this kit was made from" % os.path.basename(car_path))
    base = chop(car, kit)
    report("  chopped   %d pieces into the 7800's order" % len(kit["chop"]))
    patch = io.open(os.path.join(HERE, kit["port"]["bps"]), "rb").read()
    body, warn = bps.apply(base, patch)
    for w in warn:
        report("  warning   " + w)
    report("  patched   %s" % kit["port"]["bps"])
    if wanted:
        ps = abp.PatchSet(os.path.join(HERE, kit["port"]["options"]))
        body = ps.apply(body, list(wanted), report=lambda s: report("  " + s.strip()) if s.strip() else None)
        report("  options   %s" % ", ".join(wanted))
    body = sign7800.signed(body)
    if not sign7800.verify(body):
        raise MakeError("the signed image does not verify")
    report("  signed    NTSC 7800 signature verifies")
    out = header(body, kit) + body
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.strip().split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split("\n\n", 1)[1])
    ap.add_argument("car", nargs="?", help="the XEGS Karateka cartridge (.car or 128K .bin)")
    ap.add_argument("-o", "--out", default="karateka7800.a78", help="the .a78 to write")
    ap.add_argument("--with", dest="options", default="",
                    help="options, comma-separated (see --list)")
    ap.add_argument("--list", action="store_true", help="list the options and stop")
    args = ap.parse_args()
    kit = load_kit()
    if args.list:
        ps = abp.PatchSet(os.path.join(HERE, kit["port"]["options"]))
        for o in ps.m["options"]:
            print("  %-12s %s" % (o["id"], o["title"]))
            if o.get("note"):
                print("  %-12s %s" % ("", o["note"]))
        return 0
    if not args.car:
        ap.error("name the XEGS cartridge to make it from")
    wanted = [w for w in args.options.split(",") if w]
    known = [o["id"] for o in abp.PatchSet(os.path.join(HERE, kit["port"]["options"])).m["options"]]
    for w in wanted:
        if w not in known:
            ap.error("no option %r; the options are %s (see --list)" % (w, ", ".join(known)))
    try:
        out = make(args.car, wanted)
    except (MakeError, bps.PatchError, abp.PatchSetError, sign7800.SignError) as e:
        print("make.py: %s" % e, file=sys.stderr)
        return 1
    io.open(args.out, "wb").write(out)
    sha = hashlib.sha256(out).hexdigest()
    print("  wrote     %s (%d bytes, sha256 %s)" % (args.out, len(out), sha))
    if not wanted:
        same = sha == kit["port"]["a78_sha256"]
        print("  %s" % ("identical to the release build" if same else
                        "DIFFERS from the release build (%s)" % kit["port"]["a78_sha256"]))
        return 0 if same else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
