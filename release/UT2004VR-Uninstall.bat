@echo off
rem UT2004VR uninstaller (in the game's System folder).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UT2004VR-Uninstall.ps1" %*
set RC=%errorlevel%
echo.
pause
if not "%RC%"=="0" exit /b %RC%
rem last: the uninstaller itself
del "%~dp0UT2004VR-Uninstall.ps1" 2>nul
(goto) 2>nul & del "%~f0"
