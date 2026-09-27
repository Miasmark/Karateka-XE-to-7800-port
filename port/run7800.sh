#!/bin/bash
# Run a probe against the 7800 build, windowless:
#   port/run7800.sh probes/p7800-events.lua events
# Output in work/analysis/<name>/ (the probe's files, snapshots, run.out).
# CART: another cartridge (Windows path) instead of work/karateka7800.a78.
# WAV: record the sound to this file (in the output folder) instead of none.
# The probe gets SYM (the build's symbol file) and END (frames, default 300).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$1"; NAME="$2"
MAME="${MAME:-/c/Users/thuco/AppData/Local/Programs/MAME/mame.exe}"
OUTDIR="$HERE/work/analysis/$NAME"
mkdir -p "$OUTDIR" "$HERE/work/analysis/ini"
printf 'skip_warnings             1\n' > "$HERE/work/analysis/ini/ui.ini"
w() { cygpath -w "$1"; }
KP="$(w "$HERE")"
cd "$OUTDIR"
rm -rf a7800              # snapshots from the last run
ZPMAP="$KP\work\karateka7800.zp" PROBES="$KP\probes" SYM="$KP\work\karateka7800.sym" END=${END:-300} "$MAME" a7800 -inipath "$(w "$HERE/work/analysis/ini")" \
  -cart "${CART:-$KP\work\karateka7800.a78}" -rompath "$KP\roms" -nothrottle ${WAV:+-wavwrite $WAV} $([ -n "${WAV:-}" ] || echo -sound none) -video none \
  -skip_gameinfo -snapshot_directory . -autoboot_script "$(w "$HERE/$PROBE")" ${EXTRA:-} > run.out 2>&1
if grep -q "LUA ERROR\|rror" run.out; then cat run.out; exit 1; fi
echo "done: $OUTDIR"; ls "$OUTDIR"
exit 0
