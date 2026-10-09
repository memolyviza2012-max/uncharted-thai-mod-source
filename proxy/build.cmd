@echo off
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (echo Install Visual Studio Build Tools 2022 with Desktop development with C++. & exit /b 1)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo C++ Build Tools not found. & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
pushd "%~dp0"
if not exist out mkdir out
cl /nologo /std:c++17 /LD /O2 /MT /GS /EHsc /W4 thai_language.cpp /link /DEF:version.def /OUT:out\version.dll /IMPLIB:out\version.lib
set "RESULT=%errorlevel%"
popd
exit /b %RESULT%
