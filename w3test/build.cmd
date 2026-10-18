@echo off
rem Builds w3test.asi with the VS 2022 x64 toolchain against the local WitcherNativeBridge build.
setlocal
set BRIDGE=%~dp0..\..\WitcherNativeBridge
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if not exist "%~dp0build" mkdir "%~dp0build"
cl /nologo /LD /EHsc /O2 /MD /std:c++17 /W3 /I"%BRIDGE%\include" "%~dp0w3test.cpp" /Fo"%~dp0build\\" /link /DLL /OUT:"%~dp0build\w3test.asi" "%BRIDGE%\build\Release\WitcherNativeBridge.lib" || exit /b 1
echo BUILD_OK
