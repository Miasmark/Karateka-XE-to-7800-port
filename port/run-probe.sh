#!/bin/bash
# Run a probe over the standard set of original-game runs, in parallel:
#   the scripted player in scenes 1, 2, 3, 4 and 6 (6,000 frames each; scenes
#   other than 1 reached by substituting the scene number at game start), and
#   the two human playthroughs in inp/ (xe-01-inv.inp to 75,650 frames with
#   xe-invincible.lua; xe-01-easy.inp, which reaches the ending, to 31,000
#   frames with xe-easy.lua).
#
#   port/run-probe.sh probes/xe-census.lua census
#   port/run-probe.sh probes/xe-origin.lua origin
#
# Output: work/analysis/<name>/<name>{1,2,3,4,6,U,E}.* plus run*.out logs.
# MAME runs windowless with the imperfect-graphics warning skipped.
# Env: SCENES (default "1 2 3 4 6"), END (default 6000), NOREC=1 to skip the
# recordings, MAME (default the user's install).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$1"; NAME="$2"
MAME="${MAME:-/c/Users/thuco/AppData/Local/Programs/MAME/mame.exe}"
OUTDIR="$HERE/work/analysis/$NAME"
mkdir -p "$OUTDIR" "$HERE/work/analysis/ini"
printf 'skip_warnings             1\n' > "$HERE/work/analysis/ini/ui.ini"
w() { cygpath -w "$1"; }
KP="$(w "$HERE")"
export OPT="$(w "$HERE/probes/optable.lua")"
common=(-inipath "$(w "$HERE/work/analysis/ini")" -cart "$KP\\work\\Karateka_16header.bin"
        -rompath "$KP\\roms" -nothrottle -sound none -video none -skip_gameinfo
        -autoboot_script "$(w "$HERE/$PROBE")")
cd "$OUTDIR"
for n in ${SCENES:-1 2 3 4 6}; do
  SCENE=$n OUT=$NAME$n END=${END:-6000} "$MAME" xegs "${common[@]}" > run$n.out 2>&1 &
done
if [ -z "${NOREC:-}" ]; then
  if [ -z "${SKIPU:-}" ]; then   # SKIPU=1: the long recording only adds scenes 1-2
  PLAYBACK=1 CHEAT="$KP\\probes\\xe-invincible.lua" SCENE=1 OUT=${NAME}U END=75650 \
    "$MAME" xegs "${common[@]}" -input_directory "$KP\\inp" -playback xe-01-inv.inp > runU.out 2>&1 &
  fi
  PLAYBACK=1 CHEAT="$KP\\probes\\xe-easy.lua" SCENE=1 OUT=${NAME}E END=31000 \
    "$MAME" xegs "${common[@]}" -input_directory "$KP\\inp" -playback xe-01-easy.inp > runE.out 2>&1 &
fi
wait
if grep -l "LUA ERROR" run*.out >/dev/null 2>&1; then
  echo "Lua errors in: $(grep -l 'LUA ERROR' run*.out | tr '\n' ' ')"
  exit 1
fi
echo "done: $OUTDIR"
ls "$OUTDIR" | grep -v '^run' | wc -l
exit 0
