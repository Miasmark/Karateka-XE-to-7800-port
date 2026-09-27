#!/usr/bin/env python3
"""Verify fixed-bank (bank 7) contents of the CURRENT build against the
authoritative SuperGame layout, and inspect the $FF90 stall point."""
import sys

rom = open('/Users/thucom/Documents/Atari 7800/Karateka-Port/build/KaratekaXE.a78','rb').read()
if rom[:4] == b'ATARI':
    rom = rom[128:]

banks = [rom[i*16384:(i+1)*16384] for i in range(8)]
b7 = banks[7]

def dump(off, n, label):
    print(f"{label}  ${off:04X}: " + " ".join(f"{b7[off+i]:02X}" for i in range(n)))

print("="*70)
print("FIXED BANK 7 ($C000-$FFFF) - actual bytes in current .a78")
print("="*70)
dump(0x0000, 16, "C000 (Common lhs)")
dump(0x2000, 16, "E000 (upper lhs)")
dump(0x3F80, 0x18, "FF80 *signature zone*")
dump(0x3F90, 0x20, "FF90 *pre-sign boot stub? / post-sign sig?*")
dump(0x3FD0, 0x10, "FFD0")
dump(0x3FF0, 0x10, "FFF0")
print()
print("Key Q: are FF80-FFF7 sig bytes (Rabin) or boot code?")
print("  - If sig bytes (high entropy, no clean opcodes) -> boot stub was CLOBBERED by sign7800")
print("  - If boot code (LDX/JSR/etc patterns) -> signature lives elsewhere")
