#!/bin/bash
# The regression check: scenes 1-4 on the port against the original, byte for
# byte, with the scripted player (playkey.lua, FIREFLAG=1 INJECT=1).
#   port/regress.sh        the port only (the original's dumps are reused)
#   port/regress.sh xe     the original's dumps too
# Scene 1 at flips 300/449/600/800, scenes 2-4 at 250/500/800.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
A=work/analysis
if [ "${1:-}" = xe ] || [ ! -f $A/f1xe/fbk800.bin ]; then
  MACHINE=xe FIREFLAG=1 INJECT=1 KEYN=300,449,600,800 END=12000 port/runxe.sh probes/playkey.lua f1xe >/dev/null &
  for s in 2 3 4; do MACHINE=xe SCENE=$s FIREFLAG=1 INJECT=1 KEYN=250,500,800 END=30000 port/runxe.sh probes/playkey.lua f${s}xe >/dev/null & done
fi
# a run that dies before its dumps must not leave the last run's to compare
rm -f $A/f178/fbk*.bin $A/f278/fbk*.bin $A/f378/fbk*.bin $A/f478/fbk*.bin
FIREFLAG=1 INJECT=1 KEYN=300,449,600,800 END=18000 port/run7800.sh probes/playkey.lua f178 >/dev/null &
for s in 2 3 4; do SCENE=$s FIREFLAG=1 INJECT=1 KEYN=250,500,800 END=45000 port/run7800.sh probes/playkey.lua f${s}78 >/dev/null & done
wait
for n in 300 449 600 800; do echo "s1 $n $(python port/fbcompare.py $A/f1xe/fbk$n.bin $A/f178/fbk$n.bin 2>&1 | grep -E 'buffer|Error' | tr '\n' ' ')"; done
for s in 2 3 4; do for n in 250 500 800; do echo "s$s $n $(python port/fbcompare.py $A/f${s}xe/fbk$n.bin $A/f${s}78/fbk$n.bin 2>&1 | grep -E 'buffer|Error' | tr '\n' ' ')"; done; done
