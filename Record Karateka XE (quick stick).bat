@echo off
rem ---------------------------------------------------------------------------
rem  Record Karateka XE.bat, in easy mode plus "quick stick": a trial of the
rem  control change the port may make (probes\xe-easy-latch.lua).
rem
rem  The original only looks at the stick every 6-10 frames, so a short push
rem  between two looks is lost; that is why a kick needs a long press. Here
rem  the latest push is kept and handed to the game the next time it looks,
rem  once. Holding still reads as holding.
rem
rem  Recordings are named *-easylatch.inp.  Usage as for Record Karateka XE.bat.
rem ---------------------------------------------------------------------------
setlocal
set "KXE_LATCH=1"
call "%~dp0Record Karateka XE.bat" %*
endlocal
