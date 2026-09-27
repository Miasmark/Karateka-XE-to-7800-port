@echo off
rem ---------------------------------------------------------------------------
rem  Watch a recording of the original XEGS Karateka play back.
rem
rem  Usage:   Play Karateka XE Recording.bat xe-01-easy
rem           (the name of a file in inp\, without .inp)
rem
rem  A recording only replays correctly under the conditions it was made in,
rem  so the script it was recorded with is loaded again, chosen by its name:
rem     *-easy   probes\xe-easy.lua        (easy mode, the current one)
rem     *-easylatch  probes\xe-easy-latch.lua  (easy mode + quick stick)
rem     *-inv    probes\xe-invincible.lua  (version 1, kept for xe-01-inv)
rem  When the recording runs out the game carries on under your control.
rem  P pauses, Esc quits (Scroll Lock first if Esc does nothing).
rem ---------------------------------------------------------------------------

setlocal
set "MAME=%LOCALAPPDATA%\Programs\MAME\mame.exe"
for %%M in ("%MAME%") do set "MAMEDIR=%%~dpM"
set "MAMEDIR=%MAMEDIR:~0,-1%"
set "HERE=%~dp0"
set "DIR=%HERE:~0,-1%"
set "CART=%DIR%\work\Karateka_16header.bin"
set "EASY=%DIR%\probes\xe-easy.lua"
set "INV=%DIR%\probes\xe-invincible.lua"
set "LATCH=%DIR%\probes\xe-easy-latch.lua"
set "INP=%DIR%\inp"

set "NAME=%~n1"
if "%NAME%"=="" (
    echo Usage: Play Karateka XE Recording.bat ^<recording name, without .inp^>
    echo.
    echo Recordings available:
    for %%F in ("%INP%\*.inp") do echo    %%~nF
    pause
    exit /b 1
)
if not exist "%INP%\%NAME%.inp" ( echo No such recording: inp\%NAME%.inp & pause & exit /b 1 )
if not exist "%MAME%" ( echo Could not find MAME at "%MAME%". & pause & exit /b 1 )

set "SCRIPT="
if /i "%NAME:~-4%"=="-inv" set "SCRIPT=-autoboot_script "%INV%""
if /i "%NAME:~-5%"=="-easy" set "SCRIPT=-autoboot_script "%EASY%""
if /i "%NAME:~-10%"=="-easylatch" set "SCRIPT=-autoboot_script "%LATCH%""

rem skip MAME's "imperfect graphics" warning: a copy of your own ui.ini with
rem skip_warnings 1, searched before MAME's folder
if not exist "%DIR%\mame-ini" mkdir "%DIR%\mame-ini"
if exist "%MAMEDIR%\ui.ini" (
    findstr /v /b /c:"skip_warnings" "%MAMEDIR%\ui.ini" > "%DIR%\mame-ini\ui.ini"
) else (
    type nul > "%DIR%\mame-ini\ui.ini"
)
(echo skip_warnings             1)>> "%DIR%\mame-ini\ui.ini"

echo Recording: inp\%NAME%.inp
if defined SCRIPT ( echo With the script it was recorded under. )
echo P pauses, Esc quits.
echo.

"%MAME%" xegs -inipath "%DIR%\mame-ini;%MAMEDIR%" -rompath "%DIR%\roms" ^
    -cart "%CART%" -skip_gameinfo -window ^
    -input_directory "%INP%" -playback "%NAME%.inp" %SCRIPT%

endlocal
