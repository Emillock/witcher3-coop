@echo off
rem Hosts a Witcher 3 co-op game: starts the Witcher Online server and a friends-only Steam lobby.
setlocal
cd /d "%~dp0"
where java >nul 2>&1 || (
  echo Hosting needs Java 21 or newer: https://adoptium.net
  echo Install it, then run this again. Friends who only join don't need Java.
  pause
  exit /b 1
)
set "NAME=Player"
if exist name.txt set /p NAME=<name.txt
set "INPUT="
set /p INPUT=Your name in the game [%NAME%]:
if defined INPUT set "NAME=%INPUT%"
>name.txt echo %NAME%
echo.
echo Keep this window open while you play. Start The Witcher 3 from Steam and load a save.
echo Friends join with "Join co-op.cmd" (you must be Steam friends). Close this window to end the session.
echo.
w3relay.exe host --server-jar "%~dp0server\WitcherServer.jar" --game-dir "%~dp0..\.." --name "%NAME%"
pause
