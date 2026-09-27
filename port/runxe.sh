#!/bin/bash
# Run a probe against the original (XEGS cartridge), windowless, no input:
#   port/runxe.sh probes/xe-snap.lua xesnap
# Output in work/analysis/<name>/. Env is passed through to the probe.
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
rm -rf xegs               # snapshots from the last run
PROBES="$KP\probes" "$MAME" xegs -inipath "$(w "$HERE/work/analysis/ini")" \
  -cart "$KP\work\Karateka_16header.bin" -rompath "$KP\roms" -nothrottle -sound none -video none \
  -skip_gameinfo -snapshot_directory . -autoboot_script "$(w "$HERE/$PROBE")" ${EXTRA:-} > run.out 2>&1
if grep -q "LUA ERROR\|rror" run.out; then cat run.out; exit 1; fi
echo "done: $OUTDIR"
exit 0
