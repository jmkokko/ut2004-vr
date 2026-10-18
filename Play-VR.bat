@echo off
rem UT2004VR launcher. Copy into the game's System folder (build.sh / build-proxy.sh do this for the lab).
rem Usage: Play-VR.bat            UT2004's main menu in the headset: pick Instant Action, gametype, map and rules
rem        Play-VR.bat MapName    straight into VRGame (deathmatch) on that map, e.g. Play-VR.bat DM-Antalus
cd /d "%~dp0"
if "%1"=="" (
  start "" UT2004.exe -log
) else (
  start "" UT2004.exe "%1?Game=UT2004VR.VRGame?SpectatorOnly=0" -log
)
