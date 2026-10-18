@echo off
rem Joins a friend's Witcher 3 co-op game through Steam (no IP address or port forwarding).
setlocal
cd /d "%~dp0"
set "NAME=Player"
if exist name.txt set /p NAME=<name.txt
set "INPUT="
set /p INPUT=Your name in the game [%NAME%]:
if defined INPUT set "NAME=%INPUT%"
>name.txt echo %NAME%
echo.
echo Looking for a Steam friend who is hosting. Keep this window open while you play,
echo then start The Witcher 3 from Steam and load a save.
echo.
w3relay.exe join --game-dir "%~dp0..\.." --name "%NAME%" %*
pause
