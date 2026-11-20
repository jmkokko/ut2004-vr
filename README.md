# UT2004VR

Half-Life: Alyx-style VR camera and locomotion for Unreal Tournament 2004 (OldUnreal patch 3374, 64-bit),
on a SteamVR headset. Walk, teleport and look around UT2004 maps in true stereo, and shoot the way you do in Alyx: the gun (the weapon's complete third-person model) is in your
right hand, and shots, beams and projectiles leave its muzzle along its barrel, with no aim assist.

## How it works
| Part | What it does |
|---|---|
| `UT2004VR/` (UnrealScript) | `VRGame` gametype; `VRPlayerController` drives the head-tracked camera, room-scale walking (the capsule follows your head), smooth locomotion, snap/smooth turn, teleport arc and crouch/jump; each eye renders into its own `ScriptedTexture` with `DrawPortal` (square pixels, correct projection), with the comfort vignette, blink fades and a hidden eye tag; `VRHUD` triggers both eye renders each frame; `VRLink` receives poses over localhost UDP. |
| `proxy/` (C++, `d3d9.dll`) | Hooks D3D9 `CreateTexture` to find the two eye render targets (left/right by the corner tag) and `Present`, copies them into D3D11 textures and submits them to SteamVR with crop bounds that turn UT's symmetric portal FOV into the real per-eye frustum. After `WaitGetPoses` it sends head, hand, stick and eye data to the game. With no headset it runs a mock pose (and `MockDemo=1` scripts the sticks) for flat testing. |

## Controls (default SteamVR bindings: Touch and HP Reverb G2, plus Index, Vive, WMR)
| Input | Action |
|---|---|
| Left stick | Move forward/back and strafe along your chair's forward. **Seated head steering:** while moving (any direction), looking aside turns the view that way, faster the bigger the look angle (`bSteerByGaze`, `SteerGain=1.5` deg/s per degree, `SteerDeadzone=8`, `SteerMaxDegPerSec=120`); the chair's forward is set at calibration / recenter |
| Left grip | Jump (in a vehicle: jump / rise) |
| Left trigger | Dodge toward where the left stick points (left/right/forward/back); ignored with the stick centred |
| Right stick back | Crouch while held (physical crouching also works); jumping or dodging stands you up until you let go. In a vehicle: duck / descend |
| Left Y | Menu (Esc): opens UT's menu, or closes the top menu page. **Hold for 0.8 s: recenter** (height and facing) |
| Left X | Scoreboard on/off (also `VRScores` or UT's show-scores key, F1): UT's own scoreboard for the game type, in the HUD layer in place of the HUD, as in 2D (also while dead). Without the original HUD (`bVROriginalHud=False`) it comes on its own curved panel that stays put while it's up (`ScoreboardDistance=1.0`, `ScoreboardWidth=1.5` m in `UT2004VR_proxy.ini`); `bVRScoreboardOriginal=False` brings back the drawn VR HUD scoreboard (`ScoresWidthDeg=40`) |
| Fire / alt-fire while spectating | Next player / back to your own camera. UT's own spectator bar ("Now viewing", name, score, how to switch) floats below eye level in front of you (`SpectatorBarDistance=1.0`, `SpectatorBarWidth=1.3`, `SpectatorBarDrop=0.3` m in `UT2004VR_proxy.ini`) |
| (automatic) | UT's game messages (first blood, sprees, pickups, kills, chat) in the VR HUD with UT's own positions, colours and fonts. `bVRMessages=False` turns them off, `VRMessageFontBoost=2` sets how many font sizes bigger than UT's choice |
| Right stick left/right | 45° snap turn (`VRSnap 30`, or `VRSnap 0` for smooth turn) |
| Right stick forward | Aim the teleport arc; release to blink there |
| Right stick click | Use: enter the vehicle or turret you stand at; in one, get out |
| Right trigger | Fire; when dead, respawn; with the menu open, click. A faint red aiming laser runs from the muzzle to whatever the gun points at; it hides while firing and fades back in (`bLaser`, `LaserBrightness=0.45`, `LaserWidth=0.6`, `LaserFadeIn=0.5`, `LaserRange`, `LaserDotSize`) |
| Right grip | Alt-fire |
| Right A | Next weapon |
| Right B | Previous weapon |
| Walk in your room | The pawn follows your head, with collision |
| **In a vehicle** | |
| Left stick | Drive and steer (forward/back = throttle, left/right = steer; hovering and flying vehicles strafe) |
| Right controller | Every vehicle, turret and gunner seat: aims, as with a weapon - the crosshair is where it points, the guns turn there and the vehicles that face their aim (Manta, Raptor, Cicada) turn toward it; your head looks around freely (`bVehicleHandAim`; False: your gaze aims and the right stick turns the Manta, Raptor and Cicada) |
| Left stick click | Horn |
| Left trigger or left grip / right stick back | Jump or rise (Manta, Raptor) / duck or descend |
| Right A / B | Next / previous seat (free seats only). Assault's vehicles keep UT's own: the fighter's next target, the turret group's next turret |
| Right trigger / grip | Fire / alt-fire |
| Turrets and gunner seats (both modes) | When the crosshair nears the side of your view (`TurretEdgeDeg=35` deg from where you look), the seat's view turns slowly toward it (`TurretEdgeTurn=3` deg/s per deg past it, up to `TurretEdgeMaxDegPerSec=45`; 0 = off) |
| Keyboard mode, any vehicle or turret | The mouse aims (the crosshair is where it aims, the guns turn there, the Manta / Raptor / Cicada turn toward it with your view, as on foot); your head looks around freely |
| **In a space fighter** (Assault) | |
| Right controller | Aims: the fighter's crosshair (the only one) follows where it points, as with a weapon; the ship turns toward it, faster the further it is off the nose (`FighterGazeGain=3` deg/s per deg), round the world's vertical like an aircraft, banking into the turn (`FighterBankPerDeg=1.5`, up to `FighterMaxBank=45`) and levelling out on target. Your head looks around freely |
| Left stick | Throttle (forward / back) and strafe |
| Left trigger + left stick left/right | Roll by hand; left grip levels the wings |
| Right stick | Nothing while the controller aims (`bVehicleHandAim=False`: pitch and yaw, as the mouse does, `FighterSteer=2000`) |
| Right A / B | Next / previous target |

**Left-handed:** Settings > Player > Weapon Hand. Controller mode: Left puts the gun in your left hand and every control on the other side (SteamVR's mirrored `/actions/lefty` bindings, A/B <-> X/Y on Touch and Reverb); Right (and Centre, Hidden) is as above. Keyboard mode: the gun sits to the right, left or in the middle, or Hidden shows none.

Index uses left B for the menu and left A for the scoreboard. WMR uses the left menu button and the left touchpad click, with the right touchpad for next weapon and the right menu button for previous weapon. Vive has no scoreboard button. Remap anything in SteamVR's Controller Bindings while the game runs. The cycle of A/B includes the Redeemer and Ion Painter.

Weapons: `[UT2004VR.VRPlayerController]` `bWeapons=False` gives travel-only mode; `GunOffset` (uu, aim space: shifts the gun relative to the controller) and `GunPitchOffset` adjust how the gun sits in
the hand. Each gun turns around its handle: the point where its third-person model hangs from a hand. Console, live, saved per
weapon: `VRGrip <forward> <right> <up>` moves the current gun in your hand (gun axes, uu ≈ 2 cm; e.g. `VRGrip -4 0 2`),
`VRGripInfo` (says when it is inherited), `VRGripReset`, `VRGunFlip` (upside down). Global: `VRGun <fwd> <right> <up>` (hand offset, aim axes),
`VRGunPitch <deg>`. In `UT2004VR.ini` they live under `[UT2004VR.VRTuning]`, e.g.
`Grips=(Gun="ShockRifle",Offset=(X=-4,Y=0,Z=2))`; `[UT2004VR.VRGame]` `ExtraWeapon=XWeapons.ShockRifle`
hands out an extra gun at spawn.

Height: `bMatchGameHeight=True` (default) puts your eyes at UT's stock eye height (82 uu ≈ 1.56 m) whatever your real
height or seated/standing; set it False for your real height. Seated, the height is calibrated from a ~1.5 s average and then slowly re-levelled
(`bSeatedAutoLevel`, `AutoLevelSeconds=15`): posture changes and tracking drift fade out, quick ducks still count. The
recenter button re-measures. `VRHeight <uu>` raises (or lowers) your eyes
relative to that, e.g. `VRHeight 10` ≈ +19 cm, saved. `VRScale <uu per m>` (default 52.5) changes the world's size around you.

HUD (UT2004's own icons and digits): health cross + health lower left, ammo + the current ammo icon lower right,
adrenaline pill + adrenaline upper right, and frags / spread to the leader / rank upper left, the match clock top centre (time left, or time played without a time limit; `bVRClock`); head-locked at a real stereo depth
(`bVRHud`, `HudDistance=2.5` m, `HudSpread=1.9` overall, `HudSize=0.85` digit and icon size, `HudTopUp=0.44` and `HudBottomUp=-0.65` row heights, `HudLower=0.05` moves the whole HUD down, messages and scoreboard included); while dead it says how to respawn.
With `bVROriginalHud=True` (the default) the headset shows the game type's own HUD instead of these items: Assault's
round and reinforcement timers, Onslaught's radar map and node row, the team health and ammo widgets... It is drawn
by a hidden copy of that HUD and captured like the scoreboard, as a flat layer where the VR HUD's corners are
(`OriginalHudScale=1.0` times as wide; it refreshes about 11 times a second). What it points at in the world is drawn
in 3D instead, on the object itself: Assault's objective markers (icon, defender shield, progress bar; blocked: icon +
distance; out of view: an arrow at the layer's edge), its tracked vehicle and game object, and an Assault turret's crosshair (with UT's green "will hit" square) on the point it hits. Assault turrets turn toward your gaze through their own steering and inertia (`ASTurretFollow=0.15` s).

Bots: `[UT2004VR.VRGame]` `BotNames=Alpha,Bravo,Charlie` uses your names in order (Alpha2… when they run out), empty keeps UT's roster names; `VRNumBots=4`, `BotSkill=2` (0 Novice … 3 Skilled … 7 Godlike); a URL `?NumBots=`/`?Difficulty=`
overrides them. When you die, pull the trigger to respawn.

Console: `VRStatus`, `VRSpeed 0.7` (walking speed with the stick, as a share of UT's; default 0.7), `VRScale 52.5` (uu per meter). Settings are saved to `System/UT2004VR.ini`.
Proxy settings live in `System/UT2004VR_proxy.ini`: `GPUShare` (1 = zero-copy D3D9Ex sharing, 0 = CPU copy fallback), `RenderScale` (default 0.65 → 2048 px per eye; 1.0 = SteamVR's recommended size), `Port`, and the test options `Mock`, `MockDemo` (1 = scripted sticks, 2 = still head, 3 = pitched and rolled head) and `DumpEyes`. `bCalib=True` in `UT2004VR.ini` shows projection-test markers.
The desktop window shows a normal mono view; keep it small (1280x720), since it costs GPU time.

## Keyboard/mouse mode
`VRKeyboard` in the console (saved), or `bKeyboardMouse=True` under `[UT2004VR.VRTuning]`:
- UT's own controls: WASD, double-tap dodge, jump, crouch, walk and your UT key bindings; the mouse turns and aims.
- The mouse aims and turns the view (yaw and pitch); the headset is freelook on top of that and never turns you, and the gun stays put in view while only the mouse moves. Press recenter or toggle the mode to
  re-centre the chair's forward.
- Each gun has its own keyboard-mode offset: `VRGrip <forward> <right> <up>` in this mode moves the current gun on screen and saves it as `KBMGrips` (separate from the controller-mode `Grips`), e.g. `VRGrip 0 0 -4` lowers it; `VRGripReset` clears it.
- The gun sits at a fixed spot in front of the chest (`KBMGunOffset`, `KBMChestBelowEyes`) and points where the mouse
  aims; shots, beams and the laser follow it. Tilting the aim with the mouse keeps it in the same place in view. When
  you move it lags a little and catches up (`GunLagMax=0.015` m, `GunLagTime=0.12` s, easing in and out over `GunLagSmooth=0.15` s; `GunLagMax=0` turns it off).
  Turning your head doesn't move it (it sits on your head without the turning arc), so it stays put in the room.
  When the headset loses its position (WMR falls back to rotation only) the eyes' turning arc is added
  (`NeckModelMode=2`; 1 always, 0 never; `NeckForward=0.09`, `NeckUp=0.10` m).
  The SteamVR controllers do nothing in this mode.
- The UT2004 desktop window needs keyboard/mouse focus (click into it).

## Menu in VR
Press Escape: UT's menu floats in the headset as a panel 1.4 m in front of where you faced, fixed in the room. In
controller mode, point the right controller at it (the menu cursor follows) and pull the trigger to click: the game
calls the control's own press/release/click handlers (buttons, tabs, checkboxes, dropdowns, lists; hold the trigger to drag a slider), so no Windows mouse input is involved and the UT2004 window doesn't need focus.
In keyboard/mouse mode, use the mouse as usual. Debug: `VRMenuDump` logs every clickable control with its position,
`VRMenuClick "0.40 0.74"` clicks at window uv.

## Recording what the headset shows
The UT2004 window mirrors one eye, with the console and menus drawn on top (`MirrorEye=0` left / `1` right / `-1` off, `MirrorFill=1` crops to fill the window,
`0` letterboxes, `MirrorZoom=1.08` widens it slightly past the lens edge) in `UT2004VR_proxy.ini`, including the HUD, gun and laser. With the VR HUD on, the window is cropped around the HUD instead
(`bMirrorFitHud=True` in `UT2004VR.ini`): centred on it and just big enough for all of it at any window aspect (`MirrorHudMargin=0.1` around its corners). Record it with game-only audio using the
universal-modder toolkit (from WSL):
```bash
um win record --exe UT2004.exe --out 'C:\caps\take1' --seconds 60
um video mux /mnt/c/caps/take1.mkv /mnt/c/caps/take1.audio.raw /mnt/c/caps/take1.json take1.mp4
```
For a 16:9 video, set the window to 1600×900 or 1920×1080 (`WindowedViewportX/Y` in `UT2004VR_Game.ini`); a very wide window
crops the top and bottom of the eye view, HUD rows included.

## Build and install (from WSL)
```bash
./build.sh         # copies UT2004VR/ to the lab install, adds EditPackages=UT2004VR, runs ucc make
./build-proxy.sh   # MSVC x64 build of d3d9.dll; installs it, openvr_api.dll, actions and Play-VR.bat
```
The lab install is `C:\UT2004-VRLab`, a copy of `C:\UnrealTournament2004`. Set `LAB=...` to target another
3374 install. UT2004.ini is left stock apart from `EditPackages` (needed by `ucc make`). VR runs only when the game
is started by `Play-VR.bat`; any other launch is plain UT2004 (the proxy passes straight through). To uninstall,
delete `System\d3d9.dll`; the rest is inert without it.

## Play
1. Install SteamVR, connect the headset and start SteamVR.
2. Run `C:\UT2004-VRLab\System\Play-VR.bat`: UT2004's main menu floats in the headset. Point and pull the trigger
   (or use the mouse in keyboard/mouse mode) through Instant Action: gametype, map, rules, bots, mutators. The game
   starts in VR whatever you pick. `Play-VR.bat DM-Rankin` (any map) skips the menu and goes straight into VRGame.
   `Play-VR.bat` runs the game with its own settings file, `UT2004VR_Game.ini`, made on its first run from
   `UT2004.ini` (delete it to start over from your current settings).

UT's startup intro (the NVIDIA logo Gorge steps out of) plays in the headset in 3D, from the intro's own camera:
you ride along with it, your head tracking on top (yaw follows the camera, the horizon stays level). The trigger
or a click skips it. `Play-VR.bat` sets `LocalMap=NvidiaLogo.ut2?Mutator=UT2004VR.VRMutator` in `UT2004VR_Game.ini` for that.

How: `VRConsole` (UT's console class, `Console=UT2004VR.VRConsole` in `UT2004VR_Game.ini`, set by `Play-VR.bat`) adds
`?Mutator=UT2004VR.VRMutator` to every game the menus start; the mutator makes you a `VRPlayerController` and names
the bots (`BotNames` under `[UT2004VR.VRGame]` applies in every gametype). In the main menus, where no
VR game runs, the console drives the menu panel and the proxy draws the headset view itself (a dark room with the
panel). Single Player (tutorials, ladder) starts its matches past the console; a local game that comes up without VR is
loaded again once with the VR mutator (a few seconds). Joining a server (including your own dedicated server) runs
without VR (the server decides the player class): you then get the game window on a big screen in the room
(`ScreenDistance=2.4`, `ScreenWidth=3.2` m in `UT2004VR_proxy.ini`), played flat with keyboard and mouse. Full VR in network games: see `docs/NETWORK_PLAN.md` (parked until local
gameplay is done).
Zoom (Lightning Gun, Sniper Rifle alt-fire): instead of narrowing the whole view, which in a headset swings the world
with every head movement, the zoomed view appears in a round scope lens with a reticle. Its centre is where the shot
goes. Controller mode: the lens sits on the gun above your hand (`ScopeOffset`, `ScopeDiameter` 0.10 m); raise the
gun to your eye. Per weapon: `VRScope <forward> <right> <up> [diameter]` in the console (metres from the gun's handle)
for the weapon in your hand, saved; `VRScope` alone shows it, `VRScopeReset` goes back to the default. While zoomed,
the right stick forward / back zooms in / out (`ScopeStickZoom=0.6`; 0 = off), up to ~24x; alt-fire again leaves the zoom. Keyboard mode: it floats ahead along your aim, facing it and level, a real object in the scene (looking around
doesn't turn it) (`ScopeKBMDistance` 0.54 m, `ScopeKBMDiameter`
0.21 m). At least `ScopeMinZoom` (2x), more as UT's zoom closes in (up to ~11x). `bScope=false` turns it off. All in
`[UT2004VR.VRPlayerController]` of `UT2004VR.ini`.
Guided Redeemer (alt-fire): you ride the warhead, your head tracked on top; the view follows its flight direction
(turns and dives as in 2D) but not its banking (`bRedeemerRoll=true` adds that). Steer with the mouse (keyboard mode)
or the right stick (`RedeemerSteer=2000`, negative inverts the pitch); fire / the trigger detonates. You look out
through a round window at its tip with UT's own scope markings (`bRedeemerWindow`, `RedeemerWindowDeg=80`,
`RedeemerWindowDist=0.6` m); it sits fixed in the warhead, so turning your head shows its rim.
In vehicles you aim with your gaze only; the mouse does nothing. Guns UT turns at a set rate (the Goliath cannon's
rubber band) lag behind your gaze, slower than in 2D (`TurretSpeed=0.6`; `InstantTurretSpeed` in turns/s slows the
ones UT snaps to the view, 0 = instant); the laser shows where the barrel really points. The Manta and Raptor turn
toward your gaze; your view follows them gently (`GazeSteerFollow=0.3`), so a glance turns you to face that spot,
and holding your head to the side keeps turning slowly. On gunner seats and turrets the view follows the vehicle
under you, never the gun.
Behind view in vehicles and on turrets (F): a chase camera at UT's own distance behind the vehicle, along its heading
(not the mouse or your head), looking down `VehicleBehindPitch=12` degrees (`VehicleBehindScale=1.0` scales the
distance); you still aim by gaze and see your character and the whole vehicle. The mouse wheel changes seats.
Behind view on foot (F / `behindview 1`): the camera sits behind you over your right shoulder (`BehindDistance=1.8`,
`BehindHeight=0.45`, `BehindRight=0.35` m), following your body's facing, not your head; it stops at walls. The gun
hangs in your character's hand, and the laser, shots and beams start at its muzzle there.
Vehicles: you sit at the vehicle's own driver camera (first person), your head tracked on top, the heading
following the vehicle (yaw only, the horizon stays level). Driving uses UT's controls (keyboard/mouse mode).
Vehicle guns aim at what you look at (UT turns them toward your view). The laser runs from the active gun's muzzle to
where its shots land; `VRVehicleLaser` switches to a small crosshair there instead (green on target, orange while a
turret is still turning or can't reach).
Alt-fire (right mouse / right grip) is each vehicle's second weapon; the mouse wheel (or A/B) changes seats: driver,
then the gunner turrets (number keys 1, 2, 3 too). Flying vehicles (Raptor) and the Manta are drawn around you
(`VehSeats` in `[UT2004VR.VRTuning]`); per vehicle, `VRSeat <forward> <right> <up>` (uu) moves your seat,
`VRSeatMesh` shows/hides the vehicle model and its guns (hide the Goliath when its turret fills the view),
`VRSeatInfo` prints both.
Gametype extras that live in their own HUD or player class (Onslaught's spawn map, Assault objectives) are not
adapted to VR; Assault crashes at round start in OldUnreal 3374 itself. In the main menus the console knows `VRKeyboard` (switch keyboard/mouse <-> controllers), `VRMenuDump` and
`VRMenuClick "u v"`. The menu panel's distance and width are `PanelDistance=0.95` and `PanelWidth=1.6` (metres) in
`UT2004VR_proxy.ini`; it curves around you like SteamVR's own panels (`PanelCurvature=0.6`: 0 flat, 1 centred on your
head; the big screen too), and is mipmapped so text doesn't shimmer; in the main menus it faces your seated calibration and stays put
(`PanelFollowDeg=30` makes it come back in front of you after looking that far away for 1.5 s; the Esc menu in a game stays where you faced).

No game files are included. Built with AI assistance (Claude Code + the universal-modder toolkit).
OpenVR SDK © Valve, BSD-3-Clause.

## License
MIT (see `LICENSE`), for UT2004VR's own code and files. Unreal Tournament 2004 belongs to Epic Games and none of
its files are included; you need your own copy. `openvr_api.dll` is Valve's OpenVR SDK (BSD 3-clause).
