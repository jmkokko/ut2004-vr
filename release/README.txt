UT2004VR @VERSION@ - Unreal Tournament 2004 in VR
==================================================

Play UT2004 in a SteamVR headset: a head-tracked stereo view, the gun in your hand (aim by pointing), smooth
locomotion and teleport, the game's own HUD and menus floating in front of you, vehicles and turrets aimed with
your controller. Seated or standing. Single player, Instant Action and every game type, against bots.

Source, issues and updates: https://github.com/jmkokko/ut2004-vr

WHAT YOU NEED
- Unreal Tournament 2004 with OldUnreal's patch 3374 (64-bit), Preview 23 or newer.
  OldUnreal's installer sets up the game with the latest patch: https://www.oldunreal.com
  Patch only: https://github.com/OldUnreal/UT2004Patches/releases
- SteamVR and a headset with motion controllers (Quest/Touch, Index, Vive, Windows Mixed Reality, HP Reverb).
- Windows 10 or 11.

INSTALL
1. Unzip this folder anywhere.
2. Run Install.bat. It finds your UT2004 folder (or asks), checks the game version and copies the mod into
   its System folder. It offers a desktop shortcut "UT2004 VR".
   (By hand instead: copy the contents of this zip's System folder into your UT2004's System folder.)

PLAY
1. Start SteamVR with the headset and controllers on.
2. Run "UT2004 VR" (or System\Play-VR.bat). The main menu floats in front of you: point and pull the trigger.
   Play-VR.bat DM-Rankin (any map name) goes straight into a VR deathmatch.
Starting UT2004 the normal way still gives the plain, flat game: VR is only on when started from Play-VR.bat.
Play-VR.bat keeps its own settings file, UT2004VR_Game.ini, made on its first run from your UT2004.ini. Delete it
to start again from your current UT2004 settings.

CONTROLS (default bindings; change them in SteamVR's Controller Bindings while the game runs)
  Left stick ............ move (your chair's forward; looking aside while moving turns you that way)
  Right stick ........... left/right: snap turn; forward: teleport arc; back (held): crouch; click: use (enter or
                          leave a vehicle)
  Right trigger / grip .. fire / alt-fire (and respawn, and click in menus)
  A / B ................. next / previous weapon (in a vehicle: next / previous seat)
  Left grip ............. jump          Left trigger + left stick: dodge
  Left Y ................ menu (hold 0.8 s: recenter height and facing)
  Left X ................ scoreboard
  Left stick click ...... horn (in a vehicle)
  In vehicles and turrets the left stick drives and the right controller aims.
  Index: left B menu, left A scoreboard. WMR: left menu button, left touchpad click; right touchpad next weapon.

LEFT-HANDED: Settings > Player > Weapon Hand: Left. The gun goes in your left hand and every control swaps sides.

KEYBOARD AND MOUSE: type VRKeyboard in the console (the ~ key) to switch between controllers and keyboard/mouse
(the headset still looks around; the mouse aims). Weapon Hand then places the gun right, left, centre or hidden.

TUNING (console, saved): VRGrip <fwd> <right> <up> moves the current gun in your hand; VRSnap <degrees> (0 =
smooth turn); VRHeight <uu> raises your eyes. Lower RenderScale in System\UT2004VR_proxy.ini if the frame rate
drops.

KNOWN LIMITS
- Offline play against bots only: online play in VR is not supported.
- An unsigned d3d9.dll can be flagged by some antivirus programs. It is UT2004VR's bridge to SteamVR (source on
  GitHub); it only acts when the game is started from Play-VR.bat.
- System\d3d9.dll replaces other d3d9 tools (ReShade, dgVoodoo) while UT2004VR is installed; the installer keeps
  theirs and the uninstaller puts it back.

UNINSTALL: run System\UT2004VR-Uninstall.bat. It removes the mod's files (and, if you want, your VR settings);
UT2004 itself is unchanged.

LICENSE: MIT (LICENSE.txt). Unreal Tournament 2004 belongs to Epic Games; no game files are included.
openvr_api.dll is Valve's OpenVR SDK (OpenVR-LICENSE.txt). Built with AI assistance (Claude Code and the
universal-modder toolkit).
