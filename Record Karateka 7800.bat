@echo off
rem ---------------------------------------------------------------------------
rem  Record a session of the 7800 PORT of Karateka in MAME, for debugging.
rem
rem  The cartridge is made fresh from the XEGS original with the patch kit
rem  (dist\karateka7800-kit\make.py) and kept next to the recording as
rem  inp\NAME.a78: a recording only replays on the cartridge it was made with,
rem  and the playback batch file loads that same cartridge again.
rem
rem  Options (the kit's --with list; python dist\karateka7800-kit\make.py
rem  --list shows them all). Default: start-level3,invincible
rem     start-level3   a new game starts at level 3; play on from there into
rem                    the finale (the hawk, the doors, Akuma, the princess).
rem                    There is no finale start: scene 4 needs what the end
rem                    of level 3 hands over, and started cold the player
rem                    stands in the doorway and never moves.
rem     start-level2   start at level 2 instead
rem     invincible     hits cost nothing, no instant deaths, no gate, no cliff
rem     easy           one hit finishes any foe
rem  To choose others:   set K78_WITH=start-level2,invincible   first
rem  For none:           set K78_WITH=none
rem
rem  Usage:   Record Karateka 7800.bat               -> inp\7800-NN.inp
rem           Record Karateka 7800.bat princess      -> inp\princess.inp
rem
rem  Controls (MAME defaults): arrow keys = joystick, Left Ctrl = fire,
rem  1 = the console's Reset, 2 = Select, Pause key... see MAME's Tab menu.
rem  Esc stops and saves (Scroll Lock first if Esc does nothing).
rem ---------------------------------------------------------------------------

setlocal
set "MAME=%LOCALAPPDATA%\Programs\MAME\mame.exe"
for %%M in ("%MAME%") do set "MAMEDIR=%%~dpM"
set "MAMEDIR=%MAMEDIR:~0,-1%"

rem %~dp0 ends with a backslash; a trailing backslash before a closing quote
rem escapes that quote on Windows and mangles the argument list.
set "HERE=%~dp0"
set "DIR=%HERE:~0,-1%"
set "CAR=%DIR%\..\karateka\Karateka.car"
set "KIT=%DIR%\dist\karateka7800-kit\make.py"
set "INP=%DIR%\inp"

if not exist "%MAME%" ( echo Could not find MAME at "%MAME%". & pause & exit /b 1 )
if not exist "%CAR%" ( echo Could not find the XEGS cartridge: "%CAR%" & pause & exit /b 1 )
if not exist "%KIT%" ( echo Could not find the patch kit: "%KIT%" & pause & exit /b 1 )
if not exist "%INP%" mkdir "%INP%"

set "WITH=%K78_WITH%"
if "%WITH%"=="" set "WITH=start-level3,invincible"
set "WITHARG=--with %WITH%"
if /i "%WITH%"=="none" set "WITHARG="

set "NAME=%~1"
if "%NAME%"=="" call :picknext
if exist "%INP%\%NAME%.inp" ( echo inp\%NAME%.inp already exists; pick another name. & pause & exit /b 1 )

echo Making the cartridge (%WITH%)...
python "%KIT%" "%CAR%" %WITHARG% -o "%INP%\%NAME%.a78"
if errorlevel 1 ( echo The patch kit failed. & pause & exit /b 1 )

rem skip MAME's once-per-launch warnings: a copy of your own ui.ini with
rem skip_warnings 1, searched before MAME's folder
if not exist "%DIR%\mame-ini" mkdir "%DIR%\mame-ini"
if exist "%MAMEDIR%\ui.ini" (
    findstr /v /b /c:"skip_warnings" "%MAMEDIR%\ui.ini" > "%DIR%\mame-ini\ui.ini"
) else (
    type nul > "%DIR%\mame-ini\ui.ini"
)
(echo skip_warnings             1)>> "%DIR%\mame-ini\ui.ini"

echo.
echo Recording to "%INP%\%NAME%.inp"
echo Play as far as you like, then press Esc to stop.
echo.

"%MAME%" a7800 -inipath "%DIR%\mame-ini;%MAMEDIR%" -rompath "%DIR%\roms" ^
    -cart "%INP%\%NAME%.a78" -skip_gameinfo -window ^
    -input_directory "%INP%" -record "%NAME%.inp"

echo.
if exist "%INP%\%NAME%.inp" (
    for %%F in ("%INP%\%NAME%.inp") do echo Saved: inp\%%~nxF  ^(%%~zF bytes^), cartridge inp\%NAME%.a78
) else (
    echo WARNING: no recording was written.
)
pause
endlocal
goto :eof

rem --- the next unused 7800-NN name, so nothing is ever overwritten ----------
:picknext
set /a N=1
:pn_loop
if %N% LSS 10 (set "NN=0%N%") else (set "NN=%N%")
if exist "%INP%\7800-%NN%.inp" (
    set /a N+=1
    goto pn_loop
)
set "NAME=7800-%NN%"
goto :eof
