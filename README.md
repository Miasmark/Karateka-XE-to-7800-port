# Karateka: Atari XE to Atari 7800 port

A port of the Atari XE Game System cartridge of *Karateka* to the Atari 7800.
The build reads your own dump of the XE cartridge and reassembles the game as
a 7800 cartridge: the game's 6502 code is relocated and rebuilt for the 7800's
memory map, its display is redrawn through MARIA, and its sound goes through
the TIA.

**This repository contains no game code or data.** You need your own copy of
the XE cartridge (`Karateka.car`) to build anything.

## Building

You need Python 3.10 or later and git.

```
git clone --recurse-submodules https://github.com/Miasmark/Karateka-XE-to-7800-port.git
cd Karateka-XE-to-7800-port
python port/build7800.py --car path/to/Karateka.car -o karateka7800.a78
```

Without `--car`, the build looks for `Karateka.car` in the repository's top
folder (git ignores it there), or in the `KARATEKA_CAR` environment variable.

Expected files:

| File | SHA-1 |
|---|---|
| `Karateka.car` (input, XE cartridge with its 16-byte CAR header) | `cddf050abc67aa2708763d781cdb247fb3bff50a` |
| `karateka7800.a78` (output) | `a140d13f7f76e86225b0c3de2c8b3b528aef0d65` |

The output is a 128 KB SuperGame cartridge with a signed ROM and an A78
header. The build also writes its symbol file, zero-page map and patch sites
to `work/`.

If you cloned without `--recurse-submodules`, run
`git submodule update --init` first. The assembler and signing tools come
from [a7800-toolkit](https://github.com/Miasmark/a7800-toolkit), pinned as a
submodule.

## Cartridge options

After a build, `port/kitopt.py` writes variants of the cartridge with options
applied and the ROM re-signed:

```
python port/kitopt.py invincible easy --cart karateka7800.a78 -o karateka7800-invincible-easy.a78
```

(`--cart` is the cartridge the build wrote; without it, `work/karateka7800.a78`.)

The options are `invincible`, `easy`, `start-level2` and `start-level3`.

`port/mkkit.py` makes a distributable patch kit (a BPS patch from the XE
cartridge, plus an options bundle). It also needs
[Anchored-Bundle-of-Patches](https://github.com/Miasmark/Anchored-Bundle-of-Patches)
beside this repository, or in `ABP_REPO`.

## Census data

To tell code from data, the build uses what the original game was seen to
do, recorded under MAME. These recordings are kept in `census/` and contain no
cartridge bytes:

- `census*.ex`: the instruction addresses each recorded run executed, with
  their counts.
- `xe-display-lists.txt`: the display lists each scene selected.
- `reloc.txt`: the pointer bytes the port relocates, by location. The bytes
  themselves are read from your cartridge at build time.

`port/mkcensus.py` regenerates this folder from the full census recordings
(`work/analysis`, made by the probes in `probes/`).

## The rest

- `port/sys7800.asm`: the 7800 system code (display lists, DLIs, sound,
  bank switching) that replaces the XE hardware.
- `port/layout7800.py`, `port/link7800.py`, `port/build7800.py`: the memory
  layout, the per-scene linker and the cartridge build.
- `probes/`: MAME Lua probes used to study the original and check the port.
- `FINDINGS.md`: the development notes, including corrections and dead ends.

The port has been tested in MAME and on the 7800 core for the Analogue
Pocket.

*Karateka* was created by Jordan Mechner and published by Broderbund; the XE
cartridge was published by Atari. This project is an unofficial fan port and
is not affiliated with any of them.
