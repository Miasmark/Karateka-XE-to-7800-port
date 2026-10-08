#!/usr/bin/env python3
"""The cartridge (work/karateka7800.a78) with the kit's options applied
(port/mkkit.py OPTIONS, at the sites the build wrote to
karateka7800.sites.json), re-signed.
    python port/kitopt.py invincible easy -o work/karateka7800-invincible-easy.a78"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkkit            # noqa: E402
import sign7800         # noqa: E402  (the toolkit's, on the path via mkkit)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("options", nargs="+")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--cart", help="the built cartridge (default work/karateka7800.a78; "
                    "its patch sites are always the last build's, work/karateka7800.sites.json)")
    a = ap.parse_args()
    work = os.path.join(HERE, "..", "work")
    cart = bytearray(open(a.cart or os.path.join(work, "karateka7800.a78"), "rb").read())
    head, body = cart[:128], cart[128:]
    sites = json.load(open(os.path.join(work, "karateka7800.sites.json")))
    opts = {o["id"]: o for o in mkkit.OPTIONS}
    for name in a.options:
        for site, before, after in opts[name]["edits"]:
            before, after = bytes.fromhex(before), bytes.fromhex(after)
            for bank, addr in sites[site]:
                off = mkkit.body_offset(bank, addr)
                if body[off:off + len(before)] != before:
                    raise SystemExit("%s at bank %d $%04X: %s, expected %s"
                                     % (site, bank, addr, body[off:off + len(before)].hex(" "), before.hex(" ")))
                body[off:off + len(after)] = after
    body = sign7800.signed(bytes(body))
    if not sign7800.verify(body):
        raise SystemExit("the signed image does not verify")
    open(a.out, "wb").write(bytes(head) + body)
    print("wrote %s (%s)" % (a.out, ", ".join(a.options)))


if __name__ == "__main__":
    main()
