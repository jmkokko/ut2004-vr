# UT2004VR development

How the mod works, how to build it, how it is tested without a headset, and how a release is made. The
development journal with every finding and dead end is [`MODLOG.md`](../MODLOG.md).

## How it works

UT2004VR has two parts that talk over localhost UDP.

| Part | What it does |
|---|---|
| `UT2004VR/` (UnrealScript package, `UT2004VR.u`) | `VRConsole` (the console class in `UT2004VR_Game.ini`) adds the VR mutator to every game the menus start and runs the headset menu in the main menus. `VRMutator` swaps in `VRPlayerController` and `VRPawn`. The controller drives the head-tracked camera, locomotion, weapons in the hand, vehicles and the HUD, and renders each eye into its own `ScriptedTexture` with `DrawPortal`, at the tracked head pose. `VRLink` receives poses and input. |
| `proxy/` (C++, `d3d9.dll`) | Loads the system `d3d9.dll` and hooks the device. It finds the two eye render targets in `CreateTexture` (square render targets; left/right from a colour tag in a corner), shares them with a D3D11 device (the game runs on D3D9Ex) and submits them to SteamVR with crop bounds that match each eye's real frustum. After `WaitGetPoses` it sends head, hands, buttons and sticks to the game. It also shows UT's menus, scoreboard and original HUD as SteamVR overlays, captured from the window. |

Only a game started with `-ini=UT2004VR_Game.ini` (by `Play-VR.bat`) gets VR: the proxy checks the command line
when it loads and otherwise forwards everything to the system `d3d9.dll` untouched.

Some details worth knowing before changing things:
- **Projection:** one render target per eye. A split viewport on the main canvas projects with the whole window's
  aspect, which stretched the image.
- **Guns:** the gun is the weapon's third-person model, measured once per weapon (bounding sphere and `tip` bone)
  so its handle sits at the controller. `VRPawn.EyePosition()` returns the muzzle, so traces, projectiles and beams
  start there. Per-weapon offsets: `[UT2004VR.VRTuning]` `Grips`, `KBMGrips`.
- **HUD capture:** the game type's own HUD is spawned hidden beside the VR HUD and drawn into the window on capture
  frames, over black and over white with a marker pixel; the proxy recovers transparency from the pair.
- **Vehicles:** UT aims guns from the controller's rotation, so the right hand's rotation becomes the camera and
  controller rotation while you sit in a vehicle.

## Building (from WSL)

Needs an OldUnreal 3374 64-bit install to build against, MSVC 2022 (x64) for the proxy, and the OpenVR SDK in
`third_party/openvr/` (headers, `lib/win64/openvr_api.lib`, `bin/win64/openvr_api.dll`).

```bash
./build.sh         # copies UT2004VR/ into the lab install, adds EditPackages=UT2004VR, runs ucc make
./build-proxy.sh   # MSVC x64 build of d3d9.dll; installs it, openvr_api.dll, the SteamVR actions and Play-VR.bat
```

The lab install is `C:\UT2004-VRLab` (set `LAB=...` for another). `UT2004.ini` there stays stock apart from
`EditPackages`. To uninstall from a lab, delete `System\d3d9.dll`; the rest is inert without it.

After changing a `config` setting or its comment, regenerate the reference:
```bash
python3 tools/gen-config-docs.py   # writes docs/CONFIGURATION.md
```

## Testing without a headset

The proxy has a simulated headset and the game runs a command chain from its ini, so a test is: write the chain,
launch, let it quit, read the log and look at the eye images.

```bash
# MockDemo f: hand held out, trigger pressed once to join; dump 12 eye images from frame 900, every 60 frames
MD=f DSTART=900 DSTEP=60 LOOPS=45 tools/vtest.sh \
  "VRGiveWeapon XWeapons.FlakCannon|VRTapBtn fire|VRDummy|exit" \
  "DM-Rankin?Game=UT2004VR.VRGame?NumBots=2?SpectatorOnly=0" \
  "TestExec step|Accessed"
```

- `tools/vtest.sh` backs up and restores every ini a run can change, and refuses to start while UT2004 runs.
  `LAB=` picks the install, `PLAIN=1` starts the plain game (the proxy must stay out of the way).
- `MockDemo` scenes (proxy ini): `4` hand gun with scripted fire, `f` hand held out and fire once, `g` gun raised
  and steady (screenshots), `6` head turned, `9` look away, `a` panel placed then headset turned, `b` fire every
  500 frames, `c` sitting down, `d`/`e` head and hand turns.
- Useful console commands for chains: `VRGiveWeapon <class>`, `VRTapBtn <use|jump|fire|alt|...> [seconds]`,
  `VRAltHold <seconds>`, `VRStick <x> <y>`, `VRSpawnVehicle <class> [distance]`, `VRActorLog <class>`,
  `VRStateLog`. Any word that is not a command (e.g. `VRDummy`) is a pause of one step.
- Eye images don't contain SteamVR overlays (menus, HUD layer, scoreboard). Check those in the headset or with
  `VRShowCapture`, which shows the captured layer in the desktop window.

## Recording what the headset shows

The window mirrors one eye (`MirrorEye`, `MirrorFill`, `MirrorZoom` in the proxy ini), cropped around the HUD
(`bMirrorFitHud`). For a 16:9 video, set `WindowedViewportX/Y` in `UT2004VR_Game.ini` to 1600×900 or 1920×1080.
With the universal-modder toolkit:
```bash
um win record --exe UT2004.exe --out 'C:\caps\take1' --seconds 60
um video mux /mnt/c/caps/take1.mkv /mnt/c/caps/take1.audio.raw /mnt/c/caps/take1.json take1.mp4
```

## Making a release

1. Bump the version in `UT2004VR/Classes/VRMutator.uc` (`Version`) and `proxy/d3d9proxy.cpp`
   (`UT2004VR_VERSION`); they must match.
2. `tools/package.sh` compiles `UT2004VR.u` against a clean, never-started install (`BUILDGAME`, default
   `C:\UT2004-Build`, on the OldUnreal patch players get today) through a temporary ini, builds the proxy and
   writes `dist/UT2004VR-<version>.zip` and its `.sha256`.
3. Install from the zip into that clean install (`Install.bat`, or `Installer\Install.ps1 -GameDir ... -Unattended
   -NoShortcut`), test with `LAB=/mnt/c/UT2004-Build tools/vtest.sh ...`, uninstall, and reset the install to
   never-started.
4. Tag `v<version>` and attach the zip and checksum to a GitHub release.

The release's own files are in `release/` (installer, uninstaller, player README).
