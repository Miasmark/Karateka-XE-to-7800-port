@echo off
rem ---------------------------------------------------------------------------
rem  Record a session of the ORIGINAL Atari XEGS Karateka in MAME, for the port.
rem
rem  Replaying a recording through the census probe shows every piece of code
rem  the game runs and every byte it writes. The scripted player never gets
rem  far, so a human playthrough is how the rest of the game gets measured.
rem  Getting part of the way is still useful: every new screen adds coverage.
rem
rem  Easy mode is on by default (probes\xe-easy.lua), so the whole game is
rem  reachable without having to be good at it:
rem     - hits cost you no health
rem     - no instant deaths: hit while running or walking, the hawk, the
rem       gate in the fortress, being knocked off the cliff
rem     - every foe goes down in one hit
rem  Those recordings are named *-easy.inp, and the playback batch loads the
rem  same script again, because a recording only replays correctly under the
rem  conditions it was made in.
rem
rem  Usage:   Record Karateka XE.bat                 -> inp\xe-NN-easy.inp
rem           Record Karateka XE.bat princess        -> inp\princess-easy.inp
rem           set KXE_CHEAT=0 first to play without it (no suffix)
rem
rem  Short recordings are fine: several sessions cover as much as one long one.
rem
rem  Controls (MAME defaults): arrow keys = joystick, Left Ctrl = fire.
rem  Fire starts a game from the title. In the game, fire toggles between
rem  running and fighting stance; with the stance up, the stick attacks.
rem  Esc stops and saves. If Esc does nothing, press Scroll Lock first:
rem  MAME hands the keyboard to the emulated computer and Scroll Lock gives
rem  it back.
rem
rem  The cartridge is the unmodified 128K image without its 16-byte .car
rem  header: MAME refuses the .car header (type 14), not the cartridge.
rem ---------------------------------------------------------------------------

setlocal
set "MAME=%LOCALAPPDATA%\Programs\MAME\mame.exe"
for %%M in ("%MAME%") do set "MAMEDIR=%%~dpM"
set "MAMEDIR=%MAMEDIR:~0,-1%"

rem %~dp0 ends with a backslash; a trailing backslash before a closing quote
rem escapes that quote on Windows and mangles the argument list.
set "HERE=%~dp0"
set "DIR=%HERE:~0,-1%"
set "CART=%DIR%\work\Karateka_16header.bin"
set "CHEAT=%DIR%\probes\xe-easy.lua"
set "INP=%DIR%\inp"

if not exist "%MAME%" ( echo Could not find MAME at "%MAME%". & pause & exit /b 1 )
if not exist "%CART%" ( echo Could not find the cartridge: "%CART%" & pause & exit /b 1 )
if not exist "%INP%" mkdir "%INP%"

set "SUFFIX=-easy"
rem KXE_LATCH=1 (set by "Record Karateka XE (quick stick).bat"): easy mode
rem plus the stick latch the port may use (probes\xe-easy-latch.lua)
if "%KXE_LATCH%"=="1" (
    set "CHEAT=%DIR%\probes\xe-easy-latch.lua"
    set "SUFFIX=-easylatch"
)
set "SCRIPT=-autoboot_script "%CHEAT%""
if "%KXE_CHEAT%"=="0" (
    set "SUFFIX="
    set "SCRIPT="
)

set "NAME=%~1"
if not "%NAME%"=="" (
    set "NAME=%NAME%%SUFFIX%"
    goto gotname
)
call :picknext
:gotname

rem skip MAME's once-per-launch "imperfect graphics" warning: a copy of your
rem own ui.ini with skip_warnings 1, searched before MAME's folder (redone
rem every launch, so changes to MAME's own ui.ini still carry over)
if not exist "%DIR%\mame-ini" mkdir "%DIR%\mame-ini"
if exist "%MAMEDIR%\ui.ini" (
    findstr /v /b /c:"skip_warnings" "%MAMEDIR%\ui.ini" > "%DIR%\mame-ini\ui.ini"
) else (
    type nul > "%DIR%\mame-ini\ui.ini"
)
(echo skip_warnings             1)>> "%DIR%\mame-ini\ui.ini"

echo Recording to "%INP%\%NAME%.inp"
if "%SUFFIX%"=="-easy" ( echo Easy mode: no damage, no instant deaths, foes go down in one hit. )
if "%SUFFIX%"=="-easylatch" ( echo Easy mode, plus quick stick: short pushes are no longer missed. )
if "%SUFFIX%"=="" ( echo No cheat. )
echo Play as far as you like, then press Esc to stop.
echo.

"%MAME%" xegs -inipath "%DIR%\mame-ini;%MAMEDIR%" -rompath "%DIR%\roms" ^
    -cart "%CART%" -skip_gameinfo -window ^
    -input_directory "%INP%" -record "%NAME%.inp" %SCRIPT%

echo.
if exist "%INP%\%NAME%.inp" (
    for %%F in ("%INP%\%NAME%.inp") do echo Saved: inp\%%~nxF  ^(%%~zF bytes^)
) else (
    echo WARNING: no recording was written.
)
pause
endlocal
goto :eof

rem --- the next unused xe-NN name, so nothing is ever overwritten ------------
:picknext
set /a N=1
:pn_loop
if %N% LSS 10 (set "NN=0%N%") else (set "NN=%N%")
if exist "%INP%\xe-%NN%%SUFFIX%.inp" (
    set /a N+=1
    goto pn_loop
)
set "NAME=xe-%NN%%SUFFIX%"
goto :eof
