@echo off
rem Builds w3relay.exe and the test-only mock steam_api64.dll (build\mock\) with the VS 2022 x64 toolchain.
setlocal
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1 || exit /b 1
if not exist "%~dp0build\mock" mkdir "%~dp0build\mock"
cl /nologo /EHsc /O2 /MT /std:c++17 /W3 /DUNICODE /D_UNICODE "%~dp0w3relay.cpp" /Fo"%~dp0build\\" /Fe"%~dp0build\w3relay.exe" /link user32.lib || exit /b 1
cl /nologo /LD /EHsc /O2 /MT /std:c++17 /W3 "%~dp0steam_mock.cpp" /Fo"%~dp0build\mock\\" /Fe"%~dp0build\mock\steam_api64.dll" || exit /b 1
echo BUILD_OK
