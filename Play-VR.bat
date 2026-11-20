@echo off
rem UT2004VR launcher: UT2004 in VR (SteamVR). Lives in the game's System folder.
rem Usage: Play-VR.bat            UT2004's main menu in the headset: pick Instant Action, gametype, map and rules
rem        Play-VR.bat MapName    straight into a VR deathmatch on that map, e.g. Play-VR.bat DM-Antalus
rem
rem VR runs only when the game is started from here: it uses its own settings file, UT2004VR_Game.ini, made on
rem the first run from your UT2004.ini (your video, audio and game settings) with UT2004VR's console and a
rem windowed desktop mirror. Starting UT2004 any other way is plain, unmodded UT2004.
rem To start the VR settings over from your current UT2004.ini, delete UT2004VR_Game.ini.
cd /d "%~dp0"
if not exist UT2004.exe (
  echo Play-VR.bat must be in UT2004's System folder, next to UT2004.exe.
  pause
  exit /b 1
)
if not exist UT2004VR_Game.ini (
  set SRC=UT2004.ini
  if not exist UT2004.ini set SRC=Default.ini
  call :makeini
  if errorlevel 1 (
    echo Could not create UT2004VR_Game.ini.
    pause
    exit /b 1
  )
)
if "%~1"=="" (
  start "" UT2004.exe -ini=UT2004VR_Game.ini
) else (
  start "" UT2004.exe "%~1?Game=UT2004VR.VRGame?SpectatorOnly=0" -ini=UT2004VR_Game.ini
)
exit /b 0

:makeini
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$t = Get-Content -LiteralPath '%SRC%';" ^
  "$t = $t -replace '^Console=XInterface\.ExtendedConsole\s*$', 'Console=UT2004VR.VRConsole';" ^
  "$t = $t -replace '^LocalMap=NvidiaLogo\.ut2\s*$', 'LocalMap=NvidiaLogo.ut2?Mutator=UT2004VR.VRMutator';" ^
  "$t = $t -replace '^StartupFullscreen=True\s*$', 'StartupFullscreen=False';" ^
  "if (-not ($t -match '^Console=UT2004VR\.VRConsole$')) { exit 1 };" ^
  "Set-Content -LiteralPath 'UT2004VR_Game.ini' -Value $t -Encoding Default"
exit /b %errorlevel%
