@echo off
rem UT2004VR installer: run it from the unzipped UT2004VR folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer\Install.ps1" %*
echo.
pause
