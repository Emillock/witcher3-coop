@echo off
rem Builds w3relay.exe and the test-only mock steam_api64.dll (build\mock\) with the VS 2022 x64 toolchain.
setlocal
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1 || exit /b 1
if not exist "%~dp0build\mock" mkdir "%~dp0build\mock"
cl /nologo /EHsc /O2 /MT /std:c++17 /W3 /DUNICODE /D_UNICODE "%~dp0w3relay.cpp" /Fo"%~dp0build\\" /Fe"%~dp0build\w3relay.exe" /link user32.lib || exit /b 1
cl /nologo /LD /EHsc /O2 /MT /std:c++17 /W3 "%~dp0steam_mock.cpp" /Fo"%~dp0build\mock\\" /Fe"%~dp0build\mock\steam_api64.dll" || exit /b 1
echo BUILD_OK
