@echo off
rem Builds d3d9.dll (x64) for UT2004VR. Run from anywhere.
setlocal
set HERE=%~dp0
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if not exist "%HERE%..\build" mkdir "%HERE%..\build"
cd /d "%HERE%..\build"
cl /nologo /O2 /MT /EHsc /std:c++17 /W3 /I "%HERE%..\third_party\openvr\headers" /LD "%HERE%d3d9proxy.cpp" ^
   /Fe:d3d9.dll /link /DEF:"%HERE%d3d9.def" "%HERE%..\third_party\openvr\lib\win64\openvr_api.lib" d3d11.lib ws2_32.lib user32.lib || exit /b 1
echo BUILD OK
