@echo off
rem ---------------------------------------------------------------------------
rem  Watch a recording of the 7800 port play back, on the cartridge it was
rem  recorded with (inp\NAME.a78, made by "Record Karateka 7800.bat").
rem
rem  Usage:   Play Karateka 7800 Recording.bat 7800-01
rem           (the name of a file in inp\, without .inp)
rem  When the recording runs out the game carries on under your control.
rem  P pauses, Esc quits (Scroll Lock first if Esc does nothing).
rem ---------------------------------------------------------------------------

setlocal
set "MAME=%LOCALAPPDATA%\Programs\MAME\mame.exe"
for %%M in ("%MAME%") do set "MAMEDIR=%%~dpM"
set "MAMEDIR=%MAMEDIR:~0,-1%"
set "HERE=%~dp0"
set "DIR=%HERE:~0,-1%"
set "INP=%DIR%\inp"

set "NAME=%~n1"
if "%NAME%"=="" (
    echo Usage: Play Karateka 7800 Recording.bat ^<recording name, without .inp^>
    echo.
    echo 7800 recordings available:
    for %%F in ("%INP%\*.a78") do if exist "%INP%\%%~nF.inp" echo    %%~nF
    pause
    exit /b 1
)
if not exist "%INP%\%NAME%.inp" ( echo No such recording: inp\%NAME%.inp & pause & exit /b 1 )
if not exist "%INP%\%NAME%.a78" ( echo Its cartridge is missing: inp\%NAME%.a78 & pause & exit /b 1 )
if not exist "%MAME%" ( echo Could not find MAME at "%MAME%". & pause & exit /b 1 )

if not exist "%DIR%\mame-ini" mkdir "%DIR%\mame-ini"
if exist "%MAMEDIR%\ui.ini" (
    findstr /v /b /c:"skip_warnings" "%MAMEDIR%\ui.ini" > "%DIR%\mame-ini\ui.ini"
) else (
    type nul > "%DIR%\mame-ini\ui.ini"
)
(echo skip_warnings             1)>> "%DIR%\mame-ini\ui.ini"

echo Recording: inp\%NAME%.inp on inp\%NAME%.a78
echo P pauses, Esc quits.
echo.

"%MAME%" a7800 -inipath "%DIR%\mame-ini;%MAMEDIR%" -rompath "%DIR%\roms" ^
    -cart "%INP%\%NAME%.a78" -skip_gameinfo -window ^
    -input_directory "%INP%" -playback "%NAME%.inp"

endlocal
