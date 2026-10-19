# MODLOG: Half-Life: Alyx-style VR in UT2004

Goal: travel through UT2004 maps in VR using Half-Life: Alyx-style camera and locomotion
(head-tracked camera, smooth locomotion relative to head or hand, snap/smooth turn, teleport arc, comfort vignette).
Done = working in the headset plus a 20-45 s clip.

## Recon (2026-10-09)
- Knowledge base: nothing on UT2004, UE2 or VR-for-old-engines. We may be the first to write it up.
- UT2004 installs:
  - `C:\UnrealTournament2004`: **OldUnreal patch v3374** (`Build.ini`: `UT2004_v3374_[2026-02-07_18.11]_e777cc6e`),
    **x64** (PE machine 0x8664), plus a SystemARM64 folder. Renderer `D3D9Drv.D3D9RenderDevice` (calls plain
    `Direct3DCreate9`). 131 maps, fullscreen 3440x1440. **This is the lab install.**
  - `G:\UT2004`: retail 3369-era, 32-bit (0x14c), OpenGL/D3D8 only.
  - `E:\UT\ut2004`: broken or partial (`UT2004.exe` is 0 bytes).
- VR runtime: **none found**. No SteamVR folder in any Steam library, no `HKLM\SOFTWARE\Khronos\OpenXR\1`
  ActiveRuntime, no `openvrpaths.vrpath`, no Oculus or Virtual Desktop install. The headset is still unknown.
- Prior art: no UT2004 or UE2 VR mod found. UEVR covers UE4.8-5.4 only. DXU24 (UE1 → UE5 bridge) is the
  nearest relative.
- Native SDK: public headers exist only for 3369 (32-bit). None found for the 64-bit 3374 build, so a
  native UnrealScript package or a custom RenderDevice for 3374 is an ABI gamble.

## Candidate routes
A. **UT2004 in VR (in-engine).** An UnrealScript mutator/PlayerController handles locomotion and camera
   (PlayerCalcView). A companion process reads OpenXR poses and streams them to UnrealScript over a localhost
   `UdpLink` (IpDrv, no native code needed). A `d3d9.dll` proxy grabs frames at Present and submits them to
   OpenXR. Stereo comes from alternate-eye rendering (the camera is offset by ±IPD/2 on alternating frames)
   unless a dual-render hook proves possible. Risks: AER shimmer, latency, HUD and weapon in 2D.
B. **UT2004 maps inside Half-Life: Alyx.** A converter turns the user's own UT2004 maps (BSP brushes, static
   meshes, terrain, textures) into a Source 2 addon that loads in Alyx Workshop Tools. This gets Alyx's real
   VR camera and locomotion for free. Converted content stays local (bring your own files), never published.

## Next
- Decide between route A and B with the user, and confirm the headset/runtime.

## Decision (2026-10-09)
- User chose **route A (UT2004 itself in VR)** with a **SteamVR headset**. Lab = `C:\UT2004-VRLab` (robocopy of the
  3374 install, 6.3 GB). Backups: `um backup` `ut2004-system-ini`, `ut2004-saves` (original install untouched).
- UnrealScript sources exported for reference to `C:\UT2004-src` (outside the repo, never committed).

## Engine facts found
- `Canvas.DrawPortal(X,Y,W,H, CamActor, Loc, Rot, optional int FOV, optional bool ClearZ)` (native 480) renders
  a full 3D view into a canvas rect. Two calls in `HUD.PostRender` = **true side-by-side stereo in one frame**
  (no alternate-eye rendering needed). FOV is an **integer**, horizontal across the portal width.
- `DrawDebugLine/Circle` do **not** show inside DrawPortal views. Sprite actors (DT_Sprite,
  `EpicParticles.Flares.SoftFlare`, STY_Additive) do, so the teleport arc uses VRArcDot sprites.
- `UdpLink` in `RMODE_Event` fell behind (4-5 datagrams/frame → input lagged > 15 s). `RMODE_Manual` plus a
  `ReadText` loop called from `PlayerTick` drains everything each tick → no lag.
- Bool arrays are not allowed in UnrealScript (use byte). `Port` collides with `InternetLink.Port`.
- The profile's default URL had `SpectatorOnly=1`, so launch with `?SpectatorOnly=0`. DeathMatch waits for
  "press fire": `bQuickStart=true` in InitGame plus `bReadyToPlay` in PostLogin.
- A hidden first-person pawn still shows its third-person weapon attachment in the portals, so travel mode
  gives no inventory and refuses weapon/ammo pickups.
- D3D9Drv (3374 x64) calls plain `Direct3DCreate9`, windowed, X8R8G8B8 backbuffer; the device vtable Present is
  index 17, Reset 16, swapchain Present 3. A local `d3d9.dll` in System/ is loaded first.
- UCC in WSL: `./UCC.exe make` works directly from `/mnt/c/...`; MSVC needs a Windows-side copy (cmd.exe
  rejects `\\wsl$` cwd).

## Verified (flat, mock pose, MockDemo=1, DM-Rankin)
- SBS stereo renders; head pose moves the camera; smooth locomotion ≈198 uu/s; snap 45° (yaw 8192) both ways;
  teleport arc visible, valid target → `VR teleport to ...` up onto a ledge; strafe; jump (PHYS_Falling);
  vignette while moving; blink fade. ~82-90 Hz paced.
- Recording: `C:\ut2004vr-build\caps\demo1.mkv`.

## Not yet verified (needs the headset)
- The OpenVR path: Submit, crop bounds math, `SETRES` to the recommended size, IVRInput bindings, hand poses.
- Comfort and scale on a real headset (UUPerMeter 52.5, MoveSpeedScale 0.45).

## Next
- User: install SteamVR, run Play-VR.bat, then send `UT2004VR_proxy.log` + `UT2004.log`.
- Later: GPU-side copy (D3D9Ex shared surface) instead of the CPU readback; skip the hidden main-view render;
  hand models at controller poses; per-eye mini HUD; weapons in hands.

## Headset run 1-2 (2026-10-09, RTX 3060, headset 2624x2572/eye, tangents l=-1.21 r=0.85 t=-1.00 b=1.02)
- Crash 1: `SETRES` from `HUD.PostRender` → "Can't change resolution while render device is locked". Fix: queue it
  and run it in `PlayerTick`.
- Proxy: `Submit` error 101 (DoNotHaveFocus) because Submit ran before the first WaitGetPoses. Fix: gate on a
  successful WaitGetPoses. D3D11 now created on `GetDXGIOutputInfo`'s adapter (the 9800X3D has an iGPU).
- Crash 2: `SETRES 3292x1360318w` → CreateDevice E_INVALIDARG. **UdpLink.ReadText does not terminate at the
  datagram end**, so leftovers of a longer earlier packet get appended to the last token. Fix: the proxy ends each
  packet with " ;" + NUL, and VRLink cuts at " ;". Res sanity limits added.
- The head read 0.8 m above the floor at spawn (seated), which turned on physical crouch. Added bAutoHeight
  (head at spawn/recenter → StandEyeMeters 1.62) and VRRecenter on the menu button (left B / Y).

## Headset run 3: smooth, but wrong perspective (pitch stretch, diagonal shear on roll, walls drift)
- Calibration rig: `bCalib` spawns white-square sprites at known yaw/pitch, and the HUD draws boxes where the math
  predicts them; mock `MockDemo=3` sends a pitched 20° / rolled 15° pose through the real conversion. The rotation
  round trip (`OrthoRotation(F, U^F, U)`) was exact.
- **Root cause: `Canvas.DrawPortal` on the main canvas projects with the whole viewport's aspect, not the portal
  rect's.** With side-by-side halves the vertical scale was 2× (the squares drew 1:2.1, at 2× the vertical
  offset) while SteamVR was told the image was undistorted.
- Also: 2D Canvas drawing between DrawPortal calls lands in the wrong place (the left eye's overlay appeared
  squashed in the right half), so the vignette had only ever been in the right eye.
- **Fix: render each eye into its own `ScriptedTexture`** (`Level.ObjectPool.AllocateObject`, `SetSize`,
  `Client`, `Revision++` each tick, `event RenderTexture` → `Tex.DrawPortal`). It has its own viewport, so the
  projection is square and the resolution is independent of the window. Verified: the squares are square and sit
  in the predicted boxes, also with pitch and roll, at 1328 and 2528 px.
- **D3D9Drv bug: drawing a ScriptedTexture on the HUD renders it but never restores the backbuffer render target.**
  Everything drawn afterwards goes into that texture (a black window, plus a squashed copy inside each eye). The
  workaround is to draw each eye as a 1×1 tile at (0,0), which lands on the hidden corner, and draw nothing else.
- The proxy finds the targets via the `CreateTexture` hook (vtable 23; RENDERTARGET, square, size = requested)
  and AddRefs them (released before Reset). Left/right comes from a 6×6 corner tag (red/blue) read at (3,3).
- Height: the first calibration happened with the headset on the desk (0.24 m). It now waits for 0.6-2.3 m, lifts
  seated players only (< 1.4 m), and leaves standing players at their real height.

## Headset run 4 (WMR headset on the Oasis driver, HP motion controllers via auto-remapped Touch bindings)
- The projection is OK now. But the player was at floor level: the Oasis log repeats "Cannot locate root anchor" (no
  room/floor reference), so the standing-universe head read below 0 m, auto height (0.6-2.3 m window) never ran,
  and physical crouch stayed on. Fix: the proxy sends a worn flag (activity level, falling back to worn after
  ~3 s); calibration accepts any reading and lifts implausible/seated heights to 1.62 m; recenter forces it.
- "SteamVR crashed when moving": vrserver.txt ends abruptly at `oasis: Registering new controller: Built-in
  Bluetooth Left` (the controllers waking up). The compositor then shut down because the server was gone. That's
  a driver-side crash, not in UT2004VR. The earlier 4-minute session: 22865 presents, 0 dropped.

## Headset run 5: correct, but it stutters when you move your head
- Compositor stats: 37532 presents, 7605 reprojected (20%); app CPU 13.0 ms (budget 11.1), GPU 5.3 ms.
- Proxy timing (mock, 2×2048²): GetRenderTargetData 8.6-9.1 ms + UpdateSubresource 3.5-3.7 ms = 12.3 ms of copying.
- Fix: **the game runs on D3D9Ex** (Direct3DCreate9Ex + CreateDeviceEx from the CreateDevice hook). MANAGED
  textures, VBs, IBs, cubes and volumes become DEFAULT+DYNAMIC (Ex has no managed pool), and the eye render targets
  are created with a shared handle → `ID3D11Device::OpenSharedResource` → submitted directly. A D3D9 event-query
  fence before Submit. The transfer now costs 0.47-0.55 ms. UT2004 renders normally on Ex (no failed creates, no
  Criticals). Shared frames verified by a D3D11 staging dump. `GPUShare=0` falls back to the CPU copy.

## Weapons, Alyx style (2026-10-10)
- UT2004 fire paths: InstantFire/ProjectileFire start at `Instigator.Location + Instigator.EyePosition()` and aim with
  `AdjustAim` (→ controller `Rotation`, plus auto-aim). Projectile spawn offsets come from `Weapon.GetViewAxes`
  (= controller rotation) × `ProjSpawnOffset` (Y and Z scaled by `Weapon.Hand`). Beams and flashes use
  `GetEffectStart() = Location + CalcDrawOffset(W) + EffectOffset` (view axes).
- Route: **VRPawn** overrides `EyePosition()` → muzzle and `CalcDrawOffset()` → muzzle minus the rotated
  EffectOffset (so GetEffectStart = muzzle). The controller `Rotation` = right-hand aim (the camera stays on the head
  via PlayerCalcView). `AdjustAim` returns the hand aim (no assist). Handedness/Hand = 0 drops the screen-space Y
  offsets. Covers every stock weapon without touching weapon classes.
- The first-person weapon is normally only `Canvas.DrawActor` in `RenderOverlays`, invisible in the eye portals. So
  the Weapon actor itself goes into the world each tick (`bHidden=false`, SetLocation/SetRotation at the hand;
  `bOnlyOwnerSee` still passes because the portal's CamActor is the pawn). `ThirdPersonActor.bHidden=true` (the old
  floating gun).
- Input: Fire() / AltFire() on press, `bFire`/`bAltFire` held, `Weapon.ClientStopFire(mode)` on release.
  New SteamVR actions fire/altfire/nextweapon/prevweapon in the I packet (fields 8-11).
- Pawn class: `PawnClass=VRPawn` in the controller defaults + a `SetPawnClass` override (the URL carries
  Class=Engine.Pawn), and `DefaultPlayerClassName` in VRGame.
- Verified (mock MockDemo=4: hand 35 cm forward, aim 10° right / 5° down, scripted trigger, DumpEyes at frames
  400/700): the Shock Rifle renders in the hand in both eyes, the primary beam leaves the muzzle along the aim, and the
  alt-fire ball lands at the predicted spot (~290 px vs 288 predicted, 10° right of centre).

## Gun alignment (user: "the gun is too far right and swings in an arc when I rotate my hand")
- Cause: UT's first-person meshes have their pivot near the camera, with the gun modelled down and to the right of it
  (and slightly yawed toward the screen centre), so rotating at the pivot swings the gun around an off-axis point.
  They are also ~1.7× real size (ShockRifle radius 57 uu, muzzle 70 uu ahead of the pivot).
- Fix: per-weapon auto calibration ~0.8 s after the raise (`GetRenderBoundingSphere` centre → `GetBoneCoords('tip')`,
  or `'flash'` on the minigun, gives the barrel axis in weapon-local space). The weapon rotation maps that barrel
  frame onto the aim frame, its centre is placed at the controller tip + GunOffset, and the muzzle =
  centre + aim × |tip − centre|. GunScale 0.6 (recalibrates after scaling). Live execs VRGun / VRGunScale / VRGunPitch.
- Verified: wrist rolling ±57° (mock) keeps the real 'tip' bone 1.7-2.1 uu off the aim line (= GunOffset.Z 2) and
  43 uu ahead of the hand; beam and ball leave the muzzle in both rolled frames.

## Console commands (user: "VRGunPitch -10 → Unrecognized command")
- I couldn't reproduce it. `ConsoleCommand("VRGunPitch -20")` from the controller (the same Player->Exec path the console
  uses) set GunPitchOffset to -3640 as expected. The typed attempt happened while the controllers were idle, but exec
  dispatch doesn't depend on that, so it's still open.
- Found instead: `SaveConfig()` on the controller (config(UT2004VR)) wrote **every inherited config var** into
  UT2004VR.ini, including [Engine.PlayerController] with the user's StatsUsername/StatsPassword and
  [Engine.Controller] Handedness. Fix: the tunables persist through a separate `VRTuning extends Object config(UT2004VR)`
  (StaticSaveConfig, applied in PostBeginPlay when bSaved). UT2004VR.ini was rewritten to only the mod's keys.

## Gun axis, take 2 (user: "the muzzle stays put but the near end still swings in an arc")
- The bounds-centre → tip axis was wrong: the bounds centre is not on the barrel (the gun body hangs below and beside
  it), which put the axis ~18° off (barrel=0.95,0.22,-0.22). The muzzle stayed on the rotation axis but the rear didn't.
- Evidence for the mesh X axis: the ShockRifle 'tip' bone's own X axis (the flash is emitted along it) = (1.00, 0, 0.02)
  in weapon space, and debug marks (bCalibGun) along the mesh X and the tip X both run down the middle of the gun body.
  Now: barrel frame = identity, the barrel line goes through the 'tip' bone along X, and the muzzle is placed on the aim
  line.
- AssaultRifle: its tip bone sits mid-body and its axis is tilted (0.93,0.17,-0.32), so AR shots start mid-gun.
  Might need a per-weapon trim later.

## Gun model, take 3 (user: "after switching weapons the alignment is off again; the gun model has no right side")
- Switching: the per-switch recalibration ran ~0.1 s after bring-up (the GunScale path forced it early), mid raise
  animation, so the bone poses were wrong. Now: calibrate **once per class, cached** (`array<GunCal>`), never mid-anim.
- Hollow model: UT's first-person meshes omit the faces a flat game never shows. Now **the third-person WeaponAttachment
  is drawn**: complete, real size. Detach it from the pawn's hand bone each tick and set
  `bOnlyDrawIfAttached=false` (true on every InventoryAttachment, or it vanishes once detached) and
  `bUseLightingFromBase=false`. The first-person Weapon stays hidden.
- Pawn bone poses are stale (our own body is never rendered): the grip measured off 'righthand' came out 28 uu sideways.
  The grip now comes from the attachment's default RelativeLocation/RelativeRotation; up = mesh +Z; barrel = 'tip' bone
  X, signed to point out of the front (away from the bounds centre). Most 3rd-person meshes point −X. A 'tip' within 6 uu
  of the centre (UTClassic sniper) or missing (translocator, ball launcher) falls back to ±X by the grip side.
- Verified (ExtraWeapon=all, MockDemo=4 with a level hand, a dump after each NextWeapon): AR, Bio, Shock, Link, Minigun,
  Flak, Rocket, Lightning, Shield are drawn upright at the hand, with effects from the muzzle, and stay 0.00-0.02 uu off
  the aim line through repeated switching.

## Gun fixes, round 4 (user: Flak and Shield upside down; the Shock beam fires from the spawn point; Lightning Gun "can't switch")
- `ShockRifle.GetEffectStart()` (and LinkGun's) use the **first-person weapon's own 'tip' bone** (−15·X) in first person.
  That actor was hidden and never moved after the switch to third-person models, so the beam started at the spawn point.
  Fix: keep the first-person Weapon rendered at 1/1000 scale (bones stay posed), rotation = aim, Location = muzzle + 15·X.
  Verified after walking 470 uu: the beam starts at the gun.
- Upside down: the mesh +Z-up rule is wrong for FlakAttachment and ShieldAttachment. `FlipGuns` (default those two)
  rolls the barrel frame 180°; the `VRGunFlip` exec toggles the current gun (persisted in VRTuning.FlipGuns).
- Lightning Gun: the user's log shows SniperAttachment selected and tracked several times (once for ~5 s), so the pickup
  and switch work. To retest.
- Round 5 (user: Rocket, Minigun and Lightning are also upside down): **every third-person model built pointing −X is
  turned over** (up = −Z). That's Bio, Minigun, Flak, Rocket, Lightning/Sniper and Shield; the +X ones (AR, Shock, Link,
  UTClassic sniper) are +Z up. The rule replaces the default flip list; `VRGunFlip` remains for exceptions. Logged up
  vectors for all 10 attachment classes match the rule.

## Beam starts, round 6 (user: the Lightning bolt follows the line of sight; the Link alt beam starts a gun-height low and a gun-length back)
- `SniperFire` with `Weapon.Hand == 0` starts the bolt at `Instigator.Location + EffectOffset.X·X` (the body, not the
  gun). Its right-handed branch uses `CalcDrawOffset + EffectOffset`, which VRPawn already maps to the muzzle, so
  `W.Hand = 1` for SniperRifle (instant-hit only, so no projectile Y offset).
- `LinkBeamEffect` (1st person) = `Weapon.GetEffectStart() − 60·aim`, and `LinkGun.GetEffectStart` (Hand 0) adds Z −14
  (−10 on the old mesh) and Y +3. VRPawn.CalcDrawOffset adds +14Z −3Y +60X back for LinkGun.
- Oracle: `bCalibGun` logs each new Emitter/xEmitter/Projectile spawned by the gun relative to the muzzle (in aim
  axes). After the fix: NewLightningBolt 0/0/0, LinkBeamEffect 0/0/0, ShockBeamEffect 0.08/0.06/−0.27, NewTracer
  0/0/0. Projectiles start 37-54 uu down the barrel (ProjSpawnOffset.X) and up to 7 uu low (its Z).
- Leftover: LightningCharge (1st-person charge glow) logs ~513 uu away, probably not visible.
- Shield Gun alt-fire was invisible: the first-person `ShieldEffect` is only drawn via `Canvas.DrawActor` in
  DrawMuzzleFlash, and `ShieldAttachment.ShieldEffect3rd` (shown/hidden by ShieldAltFire) has `bOwnerNoSee=True` and
  PHYS_Trailer on the pawn. Now: bOwnerNoSee=false, PHYS_None, no base, held at the muzzle + 12·aim, rotation = aim.
  Verified in a dump while alt-fire was held.

## Handles (user: "rotation should be around the handle, with a per-weapon x/y/z option")
- Placement changed from "barrel on the aim line" to **the handle at the hand**. The handle = GripL, the point where the
  3rd-person model hangs from the hand bone (from its default RelativeLocation/Rotation; the origin for most). The
  barrel stays parallel to the aim; shots still leave the real muzzle (TipL mapped to the world).
- Per weapon: `VRTuning.Grips` (struct array {Gun = weapon class name, Offset = gun axes fwd/right/up}),
  `VRGrip`/`VRGripInfo`/`VRGripReset`. The offset moves the gun in the hand.
- **UT console gotcha: an exec with three float params only received the first** (`VRGrip -4 0 2` → -4,0,0). Multi-value
  execs now take one string (the rest of the line) and split it themselves (VRGrip, VRGun).
- Verified: handle-to-hand distance 0.00 through ±60° wrist roll for every weapon; after `VRGrip -4 0 2` it's exactly
  (-4, 0, 2), persisted as `Grips=(Gun="ShockRifle",offset=(X=-4,Y=0,Z=2))`.

## Redeemer + super-weapons (user: "the Redeemer points 90° off and is upside down")
- **The real convention:** in hand-bone space every UT weapon points −X with its top at −Z, and an attachment's
  default `RelativeRotation` maps its model into that space. So barrel = (−1,0,0) << RR and up = (0,0,−1) << RR (the
  tip-bone X is still used when it agrees within ~45°). This reproduces every earlier per-weapon result (no RR: −X and
  −Z up; AR/Shock/Link Pitch 180: +X and +Z up), and for RedeemerAttachment (Yaw 270, Roll 180, no tip bone) it gives
  barrel +Y, up +Z, grip (0,−35,0) → tip (0,38.7,5.5).
- UT's NextWeapon/PrevWeapon skip InventoryGroup 0 (Redeemer, Ion Painter; keyboard 0), so there was no controller
  route. `CycleWeapon` now sorts every carried weapon by (group, group 0 last, GroupOffset), skips empty ammo guns, and
  switches with PendingWeapon + PutDown. GetWeapon would refuse some (it checks HasAmmo).
- Mock caveat: scripted alt-fire holds the Painter's zoom, so the auto-cycle sticks there, and firing the Redeemer
  auto-switches away. Test artefacts.

## Height vs the stock game (user: "the player seems a tad shorter")
- Stock xPawn eye above the floor = CollisionHeight 44 + BaseEyeHeight 38 = 82 uu (1.56 m at 52.5 uu/m). The user's head
  read 1.41 m; anything ≥ 1.4 m counted as "standing, keep real height" → 74 uu, 8 uu short.
- `bMatchGameHeight` (default true): calibration always sets the offset to (CollisionHeight + BaseEyeHeight)/UUPerMeter −
  head, so the eyes match the stock view height. Physical crouch still works relative to that.
- Process note: the user's own game was running during the build. UCC replaced UT2004VR.u fine (UT doesn't lock it
  after load); the mock flag I'd set in UT2004VR_proxy.ini was reverted at once, and the second launch didn't start
  (single instance).
- Follow-up ("didn't notice a change; I'm sitting"): the user's session did calibrate 1.38 m → 1.56 m (offset 0.18) and
  the eyes sat at 78-82 uu above the floor for most of it (before: 74), a ~12 cm change, easy to miss. Added
  `VRHeight <uu>` (EyeHeightBonus on top of the stock 82, saved) and pointed at VRScale for world size. The flat game
  at FOV 120 makes the world look smaller and farther than true-scale VR.
- Measured by the user (the same wall spot, a texture landmark): the VR eye level was clearly higher than the flat game.
  The log agreed: 93-94 uu for most of the session vs the stock 82. Calibration had fired ~1 s after "worn", while the
  head was still low (putting the headset on); then they sat up (or WMR drifted) by ~12 uu.
- Fix: calibrate from the average over 0.5-2.0 s of wearing; then, seated (head < 1.4 m), re-level slowly
  (`bSeatedAutoLevel`, τ = `AutoLevelSeconds` 15 s) so posture changes and drift fade out while quick ducks still work.
  Mock MockDemo=5 (1.10 m head, +0.20 m at frame 1500): 82 → 92 on sitting up → 83 after ~30 s.
- **Process mistake:** a test-poll loop matched the *previous* log, so I reverted Mock=1 while my test instance was still
  starting. It came up in real VR mode and attached to the user's running SteamVR for ~15 s before I killed it by PID.
  Rule from now on: check that no UT2004 is running, delete UT2004.log before launch, wait for a fresh marker, kill by
  PID, and only *then* revert the Mock flag.

## Control layout v2 (user's request, 2026-10-10)
- Left trigger alt-fire; left grip dodge left, right grip dodge right (always, no stick needed); left stick click
  crouch; right A jump; right B previous weapon (moved from the left stick click); the rest unchanged. New actions
  dodgeleft/dodgeright (I-packet fields 12-13); all four default binding files rewritten.
- Body heading: `BodyYaw` is the stick's basis and the pawn's yaw. While StickMY > 0.15 it turns toward the head yaw at
  `Diff·min(1, HeadingTurnRate·StickMY·dt)` per tick (rate proportional to the angle), snapping the last 64 units (integer
  steps stalled at 0.2°). It follows snap/smooth/mouse turns and resets on FaceOpenSpace. Mock MockDemo=6: looking
  60° right while still → heading unchanged; forward → 23°, 55°, 59.8°, 60°.
- Dodge: `ProcessMove(.., DCLICK_Left/Right, ..)` → UnrealPawn.Dodge, which scales by GroundSpeed. VR walking lowers
  GroundSpeed (0.45×), so the first dodge was 90 uu/s; with stock GroundSpeed on the dodge tick it's 660 uu/s (stock),
  perpendicular to the heading.
- **Ceiling bug** (user: "after some jump/dodge combination I rose to the ceiling and stayed there"): xPawn.DoJump sets
  `PlayerController.bDoubleJump = true` for the mid-air jump, and UT's PlayerMove clears it every frame. VRPlayerMove
  replaces PlayerMove and didn't clear it, so ProcessMove re-ran DoDoubleJump (`Velocity.Z = JumpZ + MultiJumpBoost =
  365`, which doesn't spend MultiJumpRemaining for a local player) every tick. The log shows constant +353 for 2 s, then
  pinned at z=506. Fix: `bDoubleJump = false` after ProcessMove. Mock MockDemo=7: one double jump at the apex, then a
  normal fall and landing.
- Gaze heading: the user's log shows BodyYaw converging on the head yaw within ~1 s whenever walking forward, yet they
  "didn't see the character turn". Likely a different intent (seated head-steering, i.e. turning the view itself);
  asked them.
- User confirmed the intent: **seated head steering**. `bSteerByGaze` (default): ChairYaw = the playspace head yaw at
  calibration/recenter; while StickMY > 0.15, PlayYaw turns by clamp((look − deadzone 8°)·SteerGain 1.5, ±120°/s)·StickMY
  per second; walking/body = PlayYaw + ChairYaw. The earlier BodyYaw-follows-gaze mode stays as bGazeHeading for when
  steering is off. Mock MockDemo=6 (look 60° right, walk 10 s): 78°/s, stops on release.
- Slow walking after "some jump/dodge combination": the log shows duck=1 whenever the speed was 79 (crouch ×0.4) instead of
  198. The left-stick-click crouch toggle fired when pushing the stick hard, and UT refuses dodges while crouched. Fix:
  the toggle only counts with |stick| < 0.5 (logged either way), and jump/dodge while crouched clears the toggle. The
  move is replayed within 0.3 s once `bIsCrouched` clears (DoJump/Dodge refuse while it's still set). Mock MockDemo=8:
  accidental click ignored, deliberate click crouches, jump stands up and jumps.
- Head steering also while walking backward (user request): condition |StickMY| > 0.15, rate × |StickMY|, still toward the
  gaze. Mock (look 60° right; 5 s forward, 5 s back): +78°/s in both halves, stops on release.

## Strafe steering + aiming laser (user requests)
- Head steering now runs for any left-stick movement (|stick| > 0.15, rate × |stick|).
- Aiming laser: `VRLaser extends xEmitter` (PT_Beam, the Ion Painter's `XEffectMat.Ion.painter_beam`, tinted red,
  size 1.2, no sound). Each tick: SetLocation(muzzle), SetRotation(aim), `mSpawnVecA` = trace hit (traces actors,
  ignores own pawn, LaserRange 12000). Plus a SoftFlare VRArcDot at the hit, scaled by distance × LaserDotSize for a
  constant angular size; hidden when the gun is inactive. Verified in dumps: a red line from the Shock and Bio muzzles to
  the aim point, matching where the shot lands.

## Bots + dying in VR (user: "add bots so I have something to shoot at")
- VRGame used to force 0 bots. InitGame now appends `?NumBots=VRNumBots` (4) and `?Difficulty=BotSkill` (2) unless the
  URL has them, and leaves DeathMatch's bot logic alone. (`NumBots` is already a GameInfo var counting live bots, so the
  config is VRNumBots.) Log: InitialBots=4 → after StartMatch NumBots=4.
- Dead: the Dead state has its own Fire (unfreeze, then ServerReStartPlayer); VRPlayerMove isn't running, so PlayerTick
  routes the trigger or alt-fire → Fire(0) with bMenuBeforeRespawn=false (a mid-game menu is useless in the headset).
  The eyes keep rendering while there's no pawn (CamActor = the controller, from where you fell), so the headset never
  freezes. The HUD allows the Dead state despite bBehindView; the leftover gun model and laser are hidden.
- Verified: `TestExec=suicide` → "dead, trigger -> respawn" → alive with a gun in the next dumps.
- Test hygiene learned: UT2004 creates `Running.ini` and deletes it on a clean exit. A killed test instance leaves it,
  so delete it after every kill (it marks a crash for the next launch). The UT2004.log buffer is lost on a kill, so
  verify with eye dumps or a long enough run.

## Keyboard/mouse mode (user feature request, 2026-10-11)
- `bKeyboardMouse` (config + VRTuning; `VRKeyboard` exec toggles). PlayerWalking.PlayerMove → KBMPlayerMove (stock
  GroundSpeed, no arc, anchor and chair yaw init) → **Super.PlayerMove**: UT's own WASD/dodge/jump/crouch, and the mouse
  through UpdateRotation (its VR override passes through in KBM) → KBMAfterMove: PlayYaw = Rotation.Yaw − ChairYaw (head
  = freelook on the mouse heading), UpdateGun.
- GunActive is true without a tracked hand in KBM. GunTip() = a body point (pawn floor + stock eye height −
  KBMChestBelowEyes) + KBMGunOffset in the aim axes (the mouse Rotation, yaw+pitch), so the gun, the muzzle, AdjustAim
  and the laser all follow the mouse. VRWeaponInput/sticks aren't used; mouse fire is UT's own bFire/Fire binding.
- Mock check (head swaying ±20°): the view turns with the head; the gun stays body-fixed and the laser points along the
  heading. Keyboard/mouse input itself is untested by me (it would mean driving the user's input).

## VR HUD (user request)
- Drawn into each eye's ScriptedTexture after the portal, with `ScriptedTexture.DrawText/TextSize` (UT2003Fonts
  FontEurostile37 / 21, a black drop shadow). Every item is a 3D point in head space (HudDistance 2.5 m forward;
  right/up in meters × HudSpread) projected per eye with the same math as the calibration boxes, so it has real stereo
  depth; a flat same-pixel overlay reads as infinitely far and fights near geometry.
- Health (colour by level) + ShieldStrength bottom-left, Controller.Adrenaline (COMBO READY at max) above, Weapon
  ItemName + AmmoAmount(0)[/AmmoAmount(1) when the alt ammo class differs] bottom-right (red ≤ 5), PRI Score/Deaths at
  the top, and a respawn hint while dead.
- Not yet verified visually: the user's game was running when it was built.
- HUD v2 (user: "icons and numbers like stock UT2004"): stock art from `HudContent.Generic.HUD` drawn with
  ScriptedTexture.DrawTile (alpha works): health cross (74,165,49,51), adrenaline pill (113,38,52,68), DigitsBig
  digits = 38×38 cells at x = 39·n (n = 10 is minus). The ammo icon = AmmoClass.default.IconMaterial/IconCoords (as in
  HudCDeathMatch). Top-left: frags, spread (HudCDeathMatch.UpdateRankAndSpread: lead over the best other score, or
  the deficit to the leader) and rank (1 + players with more score). The stock MyScoreIcon coords overlap the pill, so
  no icon there. Sizes scale with the eye texture width.
- Top row too high at HudSpread 1.9 (user): rows get their own heights, `HudTopUp` (0.56, was 0.70) and `HudBottomUp`
  (-0.56), both scaled by HudSpread; the spread/rank lines hang 0.09/0.17 below the top row.
- KBM pitch (user: "the mouse only turns horizontally; vertical turns the weapon"): view directions now go through
  `PlayDir()` = (v << ChairYaw) >> Rotation in KBM (the mouse yaw and pitch applied to the look relative to the chair), so
  mouse pitch tilts the view and the body-fixed gun stays put in view. Positions stay yaw-only (PlayToWorld).
- KBM gun drift (user: "the gun is sometimes on the left, sometimes on the right; it slides while strafing"): (1) the gun base
  was the pawn XY while the camera sits at pawn + rotated(head - anchor), and the anchor is captured at session start,
  so where the gun showed up depended on how you sat then. It now follows VRHeadWorld XY at a fixed chest height.
  (2) a one-frame lag: PlayerMove placed the gun before physics moved the pawn, so it trailed by velocity·dt (about
  5 uu strafing). RenderTexture (eye 0) now re-runs UpdateGun just before the portal renders, which helps VR mode too.
  Debug: bCalibGun logs the gun position in the eye frame (KBM, head still: constant 13/9.7/-18.8).

## Recording the headset view
- Proxy `MirrorToWindow`: after the eye targets are found, `StretchRect(eye RT → backbuffer)` before Present. The source
  rect = the eye's visible frustum (bounds), cropped around the texture centre (the straight-ahead point) to the window
  aspect (`MirrorFill=1`), or letterboxed after ColorFill (`0`). `MirrorEye` 0/1/−1. It costs one GPU blit; the mono
  main view underneath is just overwritten.
- `um win record --exe UT2004.exe` (gfxcapture + process-loopback audio) records the window; verified a 6 s take: the
  frame shows the mirrored left eye with the HUD, gun and laser. With a 1618×720 window the 2.25:1 crop cuts off the
  bottom HUD row, so recommend a 16:9 window for recording.
- Mirror off-centre (user: "the mirror shows more on the left; the HUD isn't centred; shots land right of the middle"): eye
  frusta are asymmetric (left eye l=-1.21, r=0.85), so mirroring the whole visible area put the picture centre ~10°
  left of straight ahead. Now the crop is symmetric around the texture centre: half-width min(-l, r), half-height
  min(-t, b), × MirrorZoom 1.08 (the portal renders the full ±h square, so a bit past the lens edge is still real image),
  then cropped to the window aspect. Verified at 1600×900: laser at the exact centre, symmetric HUD, bottom row visible.
- KBM regressions (user: "gun upside down at the top of the screen at start; the headset view tilts and keeps tilting while
  walking"): (1) the mouse pitch was applied about the *body's* right axis (PlayDir = (v << chair) >> Rotation), which rolls
  the view whenever the head is turned relative to the chair, and UT nudges the pitch while walking, hence the rocking.
  Now PlayDir is yaw-only and `MousePitchView` rotates the head F/U about the head's own right axis (Rodrigues), so the
  view can only tilt up/down; GetEyeView builds eye offsets/axes from VRHeadRot (same result in VR mode). (2) `CleanAim`/
  `SanitizeAim`: in KBM the aim rotation drops roll and clamps pitch to ±88° before and after UT's PlayerMove and on
  respawn. Controller-mode play leaves the hand's roll/pitch in Rotation, which turned the body gun over.
  Verified (debug exec VRTestAim 20, mock head turned 60°): headrot = pitch 3640 / yaw +60° / roll 0.
- Startup upside-down KBM gun (~1 s): the chest point was floor-based (stock eye height − drop) while the camera used the
  raw head height until the height calibration (2 s of wearing); a seated raw head sits below that point, so the gun was
  seen from below. The KBM gun height now follows VRHeadWorld.Z − KBMChestBelowEyes.
- Escape/menu pause: PlayerTick stops, so the eyes froze and UDP poses backed up. VRLink (bAlwaysTick) now calls
  `PausedVRTick` while Level.Pauser != None: drain, UpdateHeadWorld, Revision++, so tracking stays live over the frozen world.
  Verified: dumps taken while paused differ with the mock head sway. Added a once-per-second "VR kbm:" debug line
  (aim, chair, playyaw, head, gun, paused) for the still-unexplained "gun wrong after the menu".
- Mirror vertical offset (user: "the aim point is a few dozen px above centre; the HUD has room above the top row but
  the bottom row is clipped"): the crop was centred on the eye texture centre (the eye's own axis), but the HUD and a
  level aim are head-relative, and real eyes are angled a little relative to the head. The proxy now takes the head
  forward into eye space from GetEyeToHeadTransform (-(third row of R)), stores its tangents per eye, centres the
  mirror there, and logs the eye-to-head matrices once (to be confirmed from the next real session).
- Follow-up: the eye-to-head angles are negligible (0.0014 tan), and the mirror crop is exactly centred. A debug centre
  marker proved the HUD frame is centred too. The HUD asymmetry came from the user's own ini (HudTopUp=0.44,
  HudBottomUp=-0.65). The KBM aim above centre comes from the natural seated head pitch (head = freelook over the mouse
  aim): `ChairPitch` (head pitch captured with ChairYaw) is now subtracted in MousePitchView, so a level mouse aim is
  centred in the habitual head pose.
- **Console/menus over the mirror** (user: "can the console show in the mirror view?"). The proxy blit at Present
  overwrote them. Now the game draws the mirror itself: VRHUD.PostRender draws EyeTex[MirrorEye] (cropped by the
  proxy's new `K eye hx vy` packet, symmetric, MirrorZoom) as a fullscreen backdrop; then UT draws the console/menus;
  then **VRMirrorInteraction**, inserted at LocalInteractions[0] (InteractionMaster PostRenders arrays back to front, so
  index 0 is last), bumps both eye revisions and 1x1-draws them to trigger the render. Revision++ moved out of
  UpdateEyeTextures, so drawing the backdrop never re-renders a texture mid-HUD (the D3D9Drv RT-restore bug only fires on
  a render). The mirror is one frame behind the headset. Verified: `consoletoggle` shows the console over the mirror,
  and the eye dumps are clean.
- Controller-mode steering pulled left (user): in their log, walking with the head "straight" read -30° vs the chair
  forward (ChairYaw -7936 = -44°), so the steering kept turning. Cause: VRKeyboard reset bChairYawValid and the next
  tick captured the head while it looked at the keyboard to type the command; calibration also captured one instant.
  Now ChairYaw/ChairPitch = the averaged head forward over the calibration window (CalibFwdSum), the mode toggle
  keeps the chair, and recenter recalibrates through the same averaged path. Mock: "chair forward yaw 0 pitch 0".
- Laser toned down (user): width 0.6, brightness 0.45 (additive colour = translucency); hidden while bFire/bAltFire or
  Weapon.IsFiring(), then fades in linearly over LaserFadeIn 0.5 s (beam colour and dot ScaleGlow).

## VR menu panel (user request: the Escape menu as a world panel, clickable with the laser)
- Game → proxy back-channel: VRLink.ToProxy (UdpLink.SendText to 127.0.0.1:VRPort+1). UpdateMenuState sends "P 1 c" /
  "P 1 k" / "P 0" from `Player.GUIController.bActive` (PlayerTick and PausedVRTick). While the menu is open, VRHUD draws
  black instead of the mirror and the world laser is hidden.
- Proxy (non-blocking recv on 7791): when the menu opens, it places a panel (tracking space) 1.4 m ahead of the flattened
  head forward, 1.6 m wide, aspect of the window. Each frame: StretchRect(backbuffer → panel RT texture), then draws it
  into both eye RTs before the fence/submit: D3DSBT_ALL state block, RT = eye surface, no depth, XYZRHW+TEX1 quad
  projected with g_renderPose·EyeToHead and the portal tangent h, rhw = 1/depth (perspective-correct), BeginScene/EndScene.
- Pointer (controller mode): right tip-pose ray ∩ panel plane → (u, v) → SetCursorPos(ClientToScreen), trigger edge →
  SendInput LEFTDOWN/UP, only if GetForegroundWindow() == the game hwnd (from CreateDevice). The GUI handles input
  natively, so script KeyEvent injection can't click.
- Mock: a mock OpenVR pose built from the mock head. Verified (TestExec showmenu, swaying head): the menu panel shows in
  both eyes, room-fixed and shifting with the sway. Pointer and click not tested (they'd drive the user's cursor).
- Menu panel, round 2 (user: "no cursor, no beam, can't click"): (1) UT's menu cursor isn't in the captured backbuffer
  (hardware cursor in windowed mode), so the game sends "Q u v" (GUIController.MouseX/Y over the window size from VRHUD)
  every tick and the proxy draws a white/black cursor on the panel. (2) UT reads the mouse via DirectInput, so
  SetCursorPos never moved the menu cursor: the proxy now sends "U u v" (controller ray hit) and the game writes
  GUIController.MouseX/Y itself; the click stays SendInput, foreground-checked against GetAncestor(hwnd, GA_ROOT) (the
  device window is a child). (3) The proxy draws a red pointer beam (controller tip → panel hit, or 3 m) as a
  screen-space quad. Mock: the cursor shows on the panel; beam/click need the real controller.
- Menu panel round 3: (a) black borders: the game sends "R x y w h" (GUIController.ActivePage.ActualLeft/Top/Width/
  Height over the window size), and the proxy crops the StretchRect to it (+1% margin), sizes the panel aspect to it and
  maps the pointer/cursor uv through it. (b) Clicks were sent (logged), but UT ignored a press+release in one instant: the
  trigger press now sends LEFTDOWN and the release sends LEFTUP. (c) "Turns left until recenter": the log showed head yaw
  frozen at 112-113° for ~10 s (headset on the desk) while the 3 s worn fallback fired, so the height (0.94 m) and chair
  forward came from the desk. WornTime now only accumulates while the head moved in the last 1.5 s (>3 mm or ~0.6°
  per 0.5 s); a desk-still headset never calibrates. (A still mock head no longer calibrates either; use the sway mock.)
- Controller clicks round 4: the log shows press/release sent with UT in the foreground, yet nothing activates (real mouse
  clicks work in KBM). UT's GUI updates hover/focus only on mouse *move* events, and writing GUIController.MouseX/Y
  directly skips that. The proxy now sends a +-1 px relative SendInput move each frame while the ray is on the panel
  (foreground only); the game keeps setting the exact position, so there is no drift. To be confirmed by the user.
- "The panel seems to roll when I turn my head": in KBM the view gets Rot(head right axis, mousePitch - ChairPitch). The
  axis turns with the head, so relative to the room-fixed panel the world rotates differently per head yaw, which reads as
  the panel rolling. MousePitchView is skipped while bMenuOpen (the game is paused anyway). Controller mode has no such
  term; if it happens there too, it is something else (asked the user).
- Controller clicks round 5 (user: "laser beam still doesnt activate any buttons"): dropped all injected Windows input.
  On a trigger edge (menu open, controller mode) the game walks GUIController.ActivePage and takes the deepest visible
  control with bAcceptsInput, not disabled, IsInBounds() at MouseX/Y (set from the "U" pointer packet). It then calls
  `Hit.SetFocus(None); Hit.OnClick(Hit)`. Containers are searched even when the cursor is outside their bounds, because
  the midgame footer buttons hang outside their tab panel and a bounds-gated walk returned the page itself. Verified in
  mock with the sequenced TestExec `showmenu|vrmenuclick 0.40 0.74|vrmenuclick 0.26 0.54`: Exit Game opens
  UT2K4QuitPage, YES quits (clean "Exit: Exiting."). The midgame footer (1600x900): Settings 0.19, Forfeit 0.29,
  Exit Game 0.40, Spectate 0.50 (all v 0.74); close X 0.88,0.07; quit page YES 0.26,0.54 / NO 0.71,0.54.
- Test tooling: TestExec takes "a|b|c" (one step every 90 frames; frames, not Level.TimeSeconds, so it runs while
  paused). Exec `VRMenuDump` (controls with captions + centre uv) and `VRMenuClick "u v"` (one string: two float exec
  params parsed the second as 0). Launch tests need `?SpectatorOnly=0` (otherwise a spectator, no pawn, TestExec never
  fires). UT2004.log seen from WSL stays at 11 lines while the game runs, even with -forcelogflush; it is complete
  after a clean exit, so end test sequences with `exit`.
- Mode precedence: bKeyboardMouse is saved only in [VRTuning] (what VRKeyboard writes); the controller copy is no
  longer a config var. The old OR with a stale controller-section bKeyboardMouse=True made VRKeyboard-off not stick.
- Menu controls round 6 (user: "settings tabs don't react to the beam in controller mode"). From the exported
  XInterface source (`ucc batchexport XInterface.u class uc C:\ut2004-src\XInterface`, outside the repo):
  GUITabControl keeps its GUITabButtons in `TabStack` and GUIMultiOptionList its rows in `Elements`, neither in
  `Controls`, so the walk never saw them. MenuHit now also searches those (Elements only where ElementVisible(i)),
  and tries a container's `FocusedControl` first, so an open dropdown list beats the checkbox under it, as natively.
  Every control acts on Controller.MouseX/Y, so the trigger now does what native input does: press ->
  SetFocus, MenuStateChange(MSAT_Pressed), OnMousePressed(ctl,false); held -> OnCapturedMouseMove(dx,dy) if
  bCaptureMouse (slider/scrollbar drags); release -> OnMouseRelease, then OnClick if still IsInBounds().
  Verified in mock (VRMenuClick = press+release): Settings -> Audio tab (active tab 'Audio'), checkbox on and back off,
  combo button opens the list (4 items), a list row picks "Safe Mode", a click on the Music Volume slider sets 0.30.
  Settings write UT2004.ini on change: back it up before such tests (restored here).

## Rebound controls + VR scoreboard (user's layout, 2026-10-11)
- Actions: `dodgeleft`/`dodgeright` replaced by `dodge` (I packet field 12) and `scoreboard` (field 13); the packet
  layout is unchanged. New `bindings_hpmotioncontroller.json` (a copy of the Touch one), so HP G2 controllers get
  the layout without SteamVR's Touch conversion.
- Jump = left stick click, gated on |move stick| < 0.5 (the old crouch-click guard). Crouch = left grip held
  (`bCrouchNow = grip && !bCrouchSuppressed || head low`); a jump/dodge while crouched still stands up and replays the
  move (PendingStandMove, now with PendingDodge), and sets bCrouchSuppressed until the grip is released, else bDuck
  re-crouches the next tick and the move never fires. Dodge = left trigger, direction = the stick's bigger axis
  (DCLICK_Left/Right/Forward/Back, relative to the body yaw); a centred stick doesn't dodge.
- Left Y in VRButtonsTick (called from PlayerTick and PausedVRTick, so it works while the menu pauses the game):
  press with the menu open -> GUIController.CloseMenu(true); otherwise release before 0.8 s -> ShowMenu(); hold
  0.8 s -> VRRecenter (and no menu). Level.TimeSeconds is frozen while paused, but the hold only matters unpaused.
- Scoreboard: DrawVRScores in DrawVRHud (before the dead check, so it also shows while dead), when bShowVRScores
  (left X / VRScores) or myHUD.bShowScoreBoard. One projected centre point (HudPoint 0, 0.05) and everything else in
  font units (TextSize "Mg"), because the font has a fixed pixel size; laid out in metres, the Frags and Deaths
  columns overlapped. Backing = FinalBlend(FB_AlphaBlend) over a ConstantColor (0,0,0,170), created at runtime;
  ScriptedTexture DrawTile blends it. Sorted by Score then Deaths, team colours, you in yellow, at most 12 rows.
- Verified in mock: MockDemo=6 (now strafe+dodge left at 1700, right at 2000, centred at 2200 -> "dodge ignored";
  scoreboard on at 2300, off at 2600) and the eye dumps show the panel; MockDemo=8 (now hold crouch 500-900, a jump
  while walking at 1100 is ignored, a centred jump at 1300, hold crouch 1500-1800 + jump at 1600 -> falling, then
  duck stays 0 until release). Not mock-tested: left Y (short/hold), since no mock presses it.
- Scoreboard round 2 (user: "fills the whole view, hard to read"): the first layout was 24 line-heights wide and
  FontEurostile37's TextSize("Mg") height is ~62 px, so the panel was ~1500 px = ~69° of the 2688 px / 102° eye.
  Now 17 line-heights wide, and the font is picked per eye resolution and FOV: the biggest Eurostile (37/29/24/21/17/14/
  12/11) whose panel fits `ScoresWidthDeg` (default 40). At 2688 px / 102° that picks FontEurostile24 (line 42 px,
  panel 714 px, ~36°). Real headset: tangents l=-1.21 r=0.85, so a 101° portal, the same as the mock.

## Respawn fixes (2026-10-11/12)
- While dead, UT sets myHUD.bShowScoreBoard, so the VR scoreboard shows; the respawn hint moved below it (-0.33).
- Mock dumps confirm the respawn hint now sits under the scoreboard while dead.
- BotNames (VRGame): "" = roster names, or a comma list used in order. DeathMatch.ChangeName replaces spaces
  with "_", cuts at 20 chars and swaps a taken name for a random backup name, so VRGame strips spaces and numbers
  duplicates itself (Alpha, Alpha2).
- "Gun pointing slightly up after a respawn" (keyboard/mouse): ClientRestart sets bNeedHeight, and the height
  calibration also re-took ChairYaw/ChairPitch from where the head looked in the ~2 s after the respawn. In KBM the
  view is the head rotated by (mouse pitch - ChairPitch), so the gun sits at (ChairPitch - head pitch) in view: a
  ChairPitch taken while looking down tilts the gun up for the rest of the session (it also moved the gaze-steering
  forward in controller mode). Now bChairMeasured: the chair forward/pitch are taken at the first calibration and on
  VRRecenter only. ClientRestart also restarts the height average (WornTime <= 0.5, sums cleared): before, a respawn
  calibrated from 1 sample since WornTime was already past the 2 s gate.
- Test tooling: UT's `suicide` command does nothing in this game (no death logged), and the first `fire` after a
  death opens UT's pre-respawn menu (bMenuBeforeRespawn, pauses). Debug execs VRDie (clears bMenuBeforeRespawn,
  Pawn.Died) and VRRespawn (bFrozen = false, ServerReStartPlayer). Mock: die -> respawn logs "chair kept=True" and
  a 123-sample height; VRRecenter re-takes the chair.

## Start from UT's own menus (user request, 2026-10-12: Instant Action in the headset)
- Instant Action's UT2K4GamePageSP.StartGame does Console.DelayedConsoleCommand("start " $ URL). VRConsole (extends
  XInterface.ExtendedConsole; [Engine.Engine] Console=UT2004VR.VRConsole in the lab UT2004.ini, set by build.sh)
  overrides DelayedConsoleCommand and adds ?Mutator=UT2004VR.VRMutator to start/open/travel map URLs (merged into an
  existing ?Mutator= list; server addresses without "?" are left alone).
- GameInfo.PlayerControllerClassName is not config (DeathMatch defaults it to XGame.XPlayer), but Login only loads
  it when PlayerControllerClass is None: VRMutator.PostBeginPlay (mutators are created in InitGame, before Login)
  sets Level.Game.PlayerControllerClass = VRPlayerController. Also bQuickStart. GroupName="UT2004VR", so VRGame's own
  AddMutator and the console's URL mutator don't stack.
- Bot naming moved from VRGame.InitializeBot to VRMutator.ModifyPlayer (called from SetPlayerDefaults on every
  spawn): the first spawn gets its BotNames name. Config stays in [UT2004VR.VRGame] (class'VRGame'.default.*).
- Other gametypes bring their own HUD: VRPlayerController.ClientSetHUD swaps any HudCDeathMatch subclass for VRHUD
  (desktop mirror + the menu's black backdrop; the VR HUD itself is drawn into the eyes by the controller).
- Menu panel logic moved into VRMenu (Object): P/Q/R/M to the proxy, pointer, trigger press/drag/release, used by
  the controller in a game and by VRConsole in the main menus. Window size from GUIController.ResX/ResY (no canvas
  needed). ExtendedConsole overrides PostRender in its states but not Tick, so the console works from Tick.
- Main menus: VRConsole.Tick, when ViewportOwner.Actor isn't a VRPlayerController, spawns a VRLink (Link.Con = the
  console) and sends "M 1" with the menu state. The proxy then draws the headset view itself for 1.5 s per "M":
  two own square render targets (1536, not the game's eye size, so hk_CreateTexture doesn't take them for eyes;
  shared with D3D11 on D3D9Ex), ColorFill dark grey, DrawPanelInEye, the same submit path. Released on Reset.
- Port 7790: the console's link may still hold it when a game's controller binds (Entry level): VRLink retries
  BindPort every tick (up to 600), and the console destroys its link in NotifyLevelChange and when a VR controller
  exists.
- Play-VR.bat with no map opens UT's main menu; with a map it goes straight into VRGame as before.
- Proxy port: PollGame first ran before any Send(), i.e. before WSAStartup, so socket() failed and the proxy never
  heard the game ("panel socket bind failed"); it now calls WSAStartup itself and binds UDP 7791 from HookDevice,
  before any game script runs. VRLink refuses a port other than VRPort (closes; the controller and the console
  respawn their link), so a game link can't end up on the proxy's port.
- Mirror interaction: interactions outlive levels, so each game's controller added another; it now reuses one.
- TestExec: the rest of a sequence carries over a level change (class default TestExecCarry; "-" = finished), so a
  "VRConsoleCmd start <url>" step can be followed by checks in the new level. Debug exec VRConsoleCmd sends a
  command through Console.DelayedConsoleCommand, the menus' path. The game saves an empty "TestExec=" into the
  controller section, which overrides an inserted line above it: delete it first.
- Verified in mock: no-map launch -> proxy "standalone menu view", panel placed, eye dumps show UT's main menu on
  the panel in the dark room. From VRGame, "VRConsoleCmd start CTF-Face3?Game=XGame.xCTFGame?NumBots=4" -> console
  adds ?Mutator=UT2004VR.VRMutator, "VR mutator in XGame.xCTFGame", HudCCaptureTheFlag -> VRHUD, 4 bots; eye dumps show CTF-Face3 in VR with the VR HUD and the gun. Pause menu Exit
  Game -> YES still quits (VRMenu). CTF team skins log "Failed to load <skin>_0/_1" (UT's red/blue variants; the
  plain skin is used).
- User test of the menus (2026-10-12): works with the mouse; VRKeyboard was "not recognized" there (it's a
  VRPlayerController exec, and the main menus run a plain xPlayer). Console exec functions work (Console has its
  own: Type, ConsoleOpen...), so VRConsole now has VRKeyboard (saves VRTuning), VRMenuDump, VRMenuClick, and a
  config(UT2004VR) MenuTestExec sequence for testing the main menus without driving the mouse.
- "Panel a bit left of centre, should be closer": the main-menu panel was placed where the headset faced when the
  menu first came up (while putting it on). Standalone mode now re-places it after > 30 deg look-away for 1.5 s;
  PanelDistance (default 1.1, was 1.4) / PanelWidth (1.6) in the proxy ini.
- Head-locked menu panel reverted at the user's request: it caused motion sickness. Keep VR menus fixed in the room
  (world-locked); don't retry head-locking.

## The startup intro in VR, in 3D (user request: "option 3, inside the scene")
- The intro is Maps/NvidiaLogo.ut2 (UT2004.ini [URL] LocalMap), game UnrealGame.CinematicGame, controller
  CinematicPlayer (fire/alt-fire -> GotoMenu(MainMenuClass) + DISCONNECT); then Index.ut2?disconnect -> Entry (menus).
  Matinee (SceneManager, AFFECT_ViewportCamera) puts the controller itself on the camera path (StartInterpolation).
- LocalMap takes URL options: LocalMap=NvidiaLogo.ut2?Mutator=UT2004VR.VRMutator gives the intro a
  VRPlayerController (build.sh sets it). CinematicHud isn't a HudCDeathMatch, so it stays.
- VRPlayerController.IsCinematic() (no pawn and bInterpolating / bViewingMatineeCinematic / CinematicGame): the eyes
  go to the camera UT's own PlayerCalcView returns (captured there), plus the head's movement since the cinematic
  started, turned with the camera's yaw only (horizon level). The VR HUD is off; trigger/Fire/AltFire skip like
  CinematicPlayer. DrawPortal gets a VRCineCam marker at the camera as its camera actor.
- Bugs on the way: (1) the head anchor was taken before any head packet (HeadPos = 0), adding the whole head height;
  now it waits for real head data. (2) UnrealScript precedence: `A + B >> R` is `(A + B) >> R` (vector rotation
  binds looser than +), which rotated the camera's world position and put the eyes hundreds of units away: the
  logo and the legal text (a 3D plane, not HUD text) were out of view and only the grid room showed. A diagnostic
  (eyes = the desktop camera exactly) showed the portal renders everything fine.
- Mock dumps: the logo, Gorge stepping out and firing, the spider, the legal text, then the menu panel.
- "Static 3D view in a CTF game, can't look around" (after the VR intro): the intro's eye render targets stay alive
  (and keep their eye tags) after the intro; the CTF controller makes a new pair. The proxy's "newest target with
  this tag wins" demoted the old pair to eye = -3, but -3 targets were classified again (tries <= 30), so the two
  pairs kept taking the eye slots from each other and could end on the stale intro pair: a frozen CTF frame from the
  first render. A demoted target is now never classified again (tries = 1000). Mock, intro -> menu -> "VRStart
  CTF-Face3..." (console exec, the menus' path): one switch to the new pair, the view follows the head, HUD and gun.
- No pawn and not dead (waiting for the match, spectating, cinematics): IsFreeView() -> eyes at UT's own camera
  (PlayerCalcView) + head tracking (same as the intro); the trigger presses Fire (joins); in PlayerWaiting the
  controller joins by itself after 1.5 s ("press fire to start" isn't visible in the headset). HUD: "Pull the
  trigger to join". Menu-started games can log you in after bQuickStart's StartMatch, so you start waiting.
- VRConsole: VRStart <url> (debug; starts a game through DelayedConsoleCommand like the menus); MenuTestExec now
  keeps ticking inside VR games so a test can end with "exit" (UT2004.log is only complete after a clean exit).
- Still frozen for the user (real headset, intro -> Instant Action CTF/DM): their log had no height calibration,
  no gun calibration, no eye targets in any menu-started game. VRStateLog in such a game: link bound to 7790,
  packets 0. The links of unloaded levels (the intro's VRLink, the menus' console link) keep their sockets, UdpLink
  shares ports (SO_REUSEADDR-like), and Windows delivered the proxy's datagrams to a dead socket. (Earlier mock
  runs that "worked" just won the race; giving the console link its own 7792 wasn't enough.)
  Fix: every VRLink binds its own port, 7800 + a counter kept in class'VRLink'.default.PortSeq (outlives levels),
  bUseNextAvailable; it announces "N <port>" to the proxy every 0.5 s (and every 45 ticks, for paused games); the
  proxy sends each packet only to ports announced in the last 2 s (the old fixed 7790 until one has). Dead links
  don't tick, so they stop announcing and drop out. Mock, intro (7800) -> menus (VRConsoleLink 7801, standalone
  view) -> "VRStart CTF-Face3" (7802): vractive True, packets climbing, eyes + mirror + height calibrated.
- "Keyboard mode: at game start the gun points slightly right of the view centre; fine after a respawn": the
  user's log had the chair forward taken once at the start with pitch -2322 (-13 deg, looking down at the keyboard),
  i.e. from a glance down/aside. The chair forward is now its own measurement: the average gaze over 120 head
  samples (~1.3 s) with |forward.Z| < 0.17 (within ~10 deg of level), while worn; not tied to the height
  calibration. Mock: pitched-up head (MockDemo=3) -> height calibrated, no chair; level swaying head -> chair taken
  (pitch 0). VRRecenter (console, or hold Y) re-takes it.
- Still wrong when looking down at spawn: the user's log had the level-gaze chair only 70 s into the game (samples
  needed WornTime > 0.5, i.e. head motion in the last 1.5 s; sitting still at the keyboard, rarely), and meanwhile
  KBMPlayerMove's first-frame fallback chair from the downward glance (43 deg off). Now the chair samples need only
  "worn" = the proxy's worn flag (H field 11) or head motion in the last 20 s; and the fallback takes only a level
  gaze (else no chair until you look up). Mock: still head (MockDemo=2) and swaying head both get the chair at
  ~1.3 s.
- Keyboard-mode gun placement (user: "grip offsets aren't applied in keyboard mode, e.g. the Link Gun hides the
  view; guns should be lower"): GripOffsetFor applied the controller-mode Grips in both modes; those are tuned for a
  hand, and the Link Gun had none. Keyboard mode now has its own KBMGrips (VRTuning), edited by VRGrip/VRGripReset/
  VRGripInfo while in that mode; KBMGunOffset default Z -2 -> -6 (the user's ini value too).
- Menu cursor: the proxy's white square became an arrow pointer (7-point outline as 5 triangles, white over a
  1.22x black copy, tip at UT's cursor, ~0.04 m tall on the panel). Mock dump: arrow on the Single Player page.
- Known issue, not ours: Assault crashes at round start in OldUnreal 3374 (build 2026-02-07), also in the user's
  untouched C:\UnrealTournament2004 (no d3d9.dll, stock console): ASGameInfo.BeginRound -> ResetLevel ->
  LevelInfo.Reset -> ConsoleCommand("OBJ GARBAGE") -> GC TestReach -> "ASGameInfo ...: Offset mismatch". The VR
  mutator only makes it immediate (bQuickStart + auto-join). User chose to skip Assault (2026-10-13); options left
  open: a newer OldUnreal preview, or a VR Assault gametype whose ResetLevel skips the garbage collection.
  Fixed upstream in Preview 18 ("crashed the game when invoking the garbage collector from actor state code ...
  AS-Convoy ... quickstart", OldUnreal/UT2004Patches#420); see 2026-10-19 below.
- Vehicles (user: "inside any vehicle the viewpoint is inside it, can't see out"): the vehicle is the pawn, so the
  eyes came from its centre + seated head height, and Onslaught vehicles start in behind view (mesh visible). In a
  Vehicle(Pawn): bBehindView = false + V.POVChanged(self, true) on entry (UT then sets bOwnerNoSee per
  bDrawMeshInFP and hides the driver), eyes = V.GetCameraLocationStart() + (V.FPCamPos >> V.Rotation) + the head's
  moves since entry, turned with the vehicle's yaw only (relative to ChairYaw); gun model and laser hidden. Debug
  exec VREnterVehicle (nearest free non-turret vehicle, KDriverEnter). Mock, ONS-Torlan: ONSPRV (Hellbender,
  FPCamPos 20,-40,50) -> eye dumps show the cockpit, windscreen and dashboard.
- Single Player and servers (user: "SP tutorials/qualification and joining my dedicated server: the world is
  pitch black"): SP starts matches with PlayerOwner().ConsoleCommand("START ...") (UT2K4SPTab_Tutorials,
  ProfileNew), straight into the engine, so no VR mutator and the console's standalone dark room. VRConsole now
  reloads a local game level that came up without VR: Level.GetLocalURL(), minus the player's own options (Name,
  Class, Character, team, Sex - the engine adds them again, and a character name with a space
  cut the console command short: "open" then fell back to Index.ut2, every tick), plus the mutator, once per
  URL. Mock: native "start TUT-DM?quickstart=true..." -> reload -> "VR mutator in XGame.xDeathMatch", head tracked.
- Network clients (Level.Game None, NetMode client) aren't reloaded (the server decides the player class). The
  proxy's standalone mode now shows the whole window on a big screen (ScreenDistance 2.4, ScreenWidth 3.2) when no
  menu is up, instead of the bare dark room. Mock: a deathmatch with an unloadable mutator -> the flat game on the
  screen. Real VR in network games needs the hand/aim data replicated to the server: not done.
- "SP ladder: only the first game of each step comes up in 3D, retries in 2D": the reload guard was once per URL,
  and a retried match has the same URL. The guard now clears as soon as a VR controller runs (loops are already
  prevented by the reloaded URL carrying the mutator). Mock: TUT-DM, disconnect, TUT-DM again -> both reloaded.
- Vehicles 2 (user: "flying vehicles don't appear at all; vehicle guns need a crosshair; tank model blocks view"):
  Raptor/Manta hide their mesh from the driver (bOwnerNoSee) and sit you at their centre, so you saw only terrain.
  Per-vehicle seats (VRTuning VehSeats: offset + bShowMesh; Raptor and Manta show the mesh by default) set
  bOwnerNoSee=false. The eye formula was missing FPCamViewOffset (Goliath: 90 uu forward, in front of the turret).
  DrawVehicleCrosshair traces the vehicle's aim (vehicle-relative when bPCRelativeFPRotation) and draws a green
  crosshair at the hit. Execs VRSeat/VRSeatMesh/VRSeatInfo; debug VRSpawnVehicle <class> (900 uu ahead: `summon`
  drops it on you and kills you). Mock, ONS-Torlan: Raptor and Manta visible around you, Goliath view clear (barrel
  tip below), crosshair in all three.
- Vehicles 3 (user: "alt guns in vehicles? very large crosshair for flying vehicles, none in the tank; shots go
  where I look, the crosshair should be there, and smaller"): UT's ONS guns aim natively at the point the view
  camera (our head) looks at, while the old crosshair traced the controller rotation. Now it traces from the active
  gun's muzzle along its own fire rotation (ONSWeapon.CalcWeaponFire; ONSWeaponPawn.Gun for turret seats), half the
  size, orange while bCorrectAim is false (turret turning). Hidden on gunless seats (Hellbender driver).
  The mouse wheel in a vehicle calls Vehicle.NextWeapon -> PC.BehindView(true) (chase camera): BehindView and
  NextWeapon/PrevWeapon now cycle seats (SwitchWeapon(n): 1 driver, 2+ turrets); CycleWeapon (A/B) too.
  TestExec "NextWeapon" never reaches the controller's exec (not even on foot), so debug VRNextWeapon calls
  Pawn.NextWeapon. VRSeatMesh had no way to hide a vehicle UT draws in first person (Goliath): VehSeat.bHideMesh
  hides the vehicle and its Weapons (bOwnerNoSee). Mock: Goliath hull/turret hidden, crosshair on target; Hellbender
  seats 1 -> 2 -> 3 -> 1; Raptor small crosshair at the guns' aim.
- Vehicle laser (user: "crosshair looks out of place, test the laser instead"): the aim trace is shared
  (VehicleAimTrace); in vehicles the hand laser (VRLaser + dot) now runs from the gun's muzzle to the traced hit
  (UpdateLaser takes the end point, so it skips the vehicle's own hull and guns). bVehicleLaser (default on,
  VRVehicleLaser toggles) - off brings the crosshair back. Mock: Goliath laser from the barrel tip to the wall, Raptor
  beam from its gun.
- Scope (user: "alt fire zooms in some weapons, how in VR?"): a full-view zoom is a motion-sickness trap, so the
  zoomed view goes into a lens. A third ScriptedTexture (ScopeRes 512; not eye-sized, so the proxy ignores it)
  rendered from the muzzle along the barrel with FOV = lens angular size / magnification (max(ScopeMinZoom,
  DefaultFOV/FOVAngle)); VRMirrorInteraction renders it right before the eyes, which draw it as a disc (Combiner:
  colour from the scope, alpha from ScopeMask; FinalBlend alpha) plus a ScopeRing rim; duplex reticle drawn into it.
  Laser and dot hidden during the scope render (magnified, the dot covered the target). Trigger: UT's own zoom state
  (bZooming / FOVAngle < DefaultFOV), so any zooming weapon works. Found: UT advances zoom in AdjustView, called from
  Pawn.UpdateEyeHeight on UT's movement path, which VR movement skips - FOV stuck after one step; now PlayerTick runs
  AdjustView when it didn't run last frame. Test harness: TestExec can't reach giveweapon (like NextWeapon), so
  VRGiveWeapon <class>, VRAltHold <secs> (holds bAltFire like the mouse; clear bAltFire before ClientStopFire or the
  weapon restarts alt-fire and toggles the zoom off), VRZoom. Eye dumps come every 300 proxy frames: keep the state
  long enough. Distant targets look pale in the lens: that's the maps' distance fog (near ground has true colour).
  Mock: Lightning Gun 2x -> 11x, stays zoomed after release, next press ends it; ClassicSniperRifle too; keyboard
  mode lens at the aim centre. Controller-mode placement not seen in mock (the scripted hand is at chest height).
- Scope fixes (user: "sparkles in front of the lens; lens and image tilt with my head; the gun model in the centre"):
  the Lightning Gun's charge emitters (SniperRifle.chargeEmitter on the 1st-person weapon, SniperAttachment.charge on
  the 3rd-person one) sit at the tip, and UT's 1st-person weapon is kept at 1/1000 scale 15 uu ahead of the muzzle
  (for beam starts) - magnified, both filled the lens. Now hidden (with everything Attached to the weapon and the
  held model) just for the scope render, and the scope camera starts 20 uu past the muzzle. Tilt: the lens is drawn
  upright in the eye, which rolls with the head, so the scope camera's up is now the head's up (projected across the
  barrel) - the picture lines up with the world around it; the reticle is drawn turned to the gun's up (dotted lines;
  a canvas tile can't rotate). Test notes: vtest.sh's MockDemo override was single-quoted (never expanded): earlier
  "MockDemo=3/4" runs were plain mock. Eye dumps come at fixed proxy frames; `um win shot --exe UT2004.exe` of the
  window mirror (left eye) during the run catches a timed state instead. Mock (head rolled 15, pitched 20): reticle
  level with the world, bark in the lens continues the trunk outside, no gun or sparks.
- Menu -> game flash (user: "a short moment the game is rendered on the 2D screen before 3D"): the proxy's standalone
  view lasted 1.5 s after VRConsole's last "M 1", and with the menu closed (Play) that meant screen mode: the loading
  screen and first frames on the flat big screen, even with the new eyes ready. Now "M <mode>": 1 = menus (dark room
  when no menu is up), 2 = a game without VR (VRConsole: network client, or a local non-menu game; the big screen),
  0 = VRPlayerController's eyes render (sent once EyeTex and the mirror interaction exist) -> the proxy leaves the
  standalone view at once when it has an eye pair. No eyes and no standalone -> the dark room instead of nothing.
  The latest word wins (an "M 1/2" clears the "M 0" time; the intro's last M 0 made the view flip). Proxy timeline
  (mock, disconnect -> main menu -> VRStart DM): menu closed, ~1.1 s dark room, eyes classified, 3D. Non-VR local
  game (unloadable mutator) still gets the big screen.
- Guided Redeemer (user: "Redeemer needs the alt fire support too: guided flight as in 2D"): RedeemerGuidedFire
  possesses a RedeemerWarhead (a Pawn) and puts the controller in PlayerRocketing, whose PlayerMove feeds
  aTurn/aLookUp to UpdateRocketAcceleration. Eyes: a new UpdateHeadWorld branch (IsRiding) puts them at the warhead
  turned with its flight rotation minus roll (bRedeemerRoll), the head's moves since launch on top. Our state
  PlayerRocketing hides the hand gun/laser and in controller mode adds the right stick to aTurn/aLookUp
  (RedeemerSteer) and makes the trigger detonate; keyboard mode is UT's own (mouse steers, click detonates).
  UT's scope overlay (Warhead.DrawHUD) isn't drawn in VR. Debug VRStick "x y" holds the right stick 3 s. Mock: eyes
  match a 45-degree climb; stick (1,-0.5) turned right ~150 deg/s at 3000 and dove, banking ~60 deg kept out of the
  view (default now 2000); back on foot after the blast.
- Behind view on foot (user: "F: my view is almost inside the character's head; move it back and up, gun in the
  character's hands, laser/projectiles/beams from that muzzle"): the eyes stayed at the head while bBehindView
  made the pawn visible. Now UpdateHeadWorld's walking branch moves VRHeadWorld back/up/right (BehindCamera:
  along the chair's forward turned like the view, so head turns don't orbit the camera; Trace stops at walls).
  UpdateGun re-attaches the attachment with W.AttachToPawn (UT's hand bone) instead of holding it at the VR hand,
  and the muzzle (GunTarget, used by VRPawn.EyePosition/CalcDrawOffset for shots and beam starts, and the laser)
  is the attachment's 'tip' bone - the TipL-from-actor-transform estimate was off while attached. Shots still go
  along your aim. Debug VRBehind toggles it (TestExec can't reach BehindView reliably). Mock (Link Gun): camera
  behind-right, gun in hand, laser from the muzzle; muzzle ~31 uu ahead at chest height in pawn axes.
- Vehicle gun speed + Manta aim (user: "tank cannon turns too quickly, rubber band should be as in the original;
  Manta should aim horizontally along the vehicle, vertically by gaze"): measured first - the Goliath cannon already
  turned at UT's own rate (RotationsPerSecond 0.18, ~57 deg/s seen after a 60-degree head turn); the difference is
  the input: a glance moves the aim point at once, a mouse can't. TuneVehicleGuns (on entering, restored on leaving):
  RotationsPerSecond * TurretSpeed (0.6), bInstantRotation guns -> InstantTurretSpeed turns/s (0.75). Mock: cannon
  ~37 deg/s. Manta: UT aims vehicle guns along the cached view (PlayerCalcView/CacheCalcView), so for
  AimAlongVehicle classes the view's yaw is the vehicle's (pitch stays the gaze's); eyes are unaffected (they use
  VRHeadRot). Mock: head 60 deg right, plasma guns stay at the vehicle's yaw, pitch follows the gaze.
- Turret aim split (user: "all turret-like weapons: gaze only for vertical aim and where you look, mouse for
  horizontal; both moving the view horizontally promotes motion sickness"): the aim view (PlayerCalcView's cached
  rotation, which UT's vehicle guns trace along) now takes its yaw from the mouse (MouseAimYaw; converted for
  bPCRelativeFPRotation seats) and its pitch from the gaze, in keyboard mode; Manta stays AimAlongVehicle. Found:
  gunner seats/turrets run PlayerTurreting, where the mouse turns the seat pawn itself and copies it to the
  controller - and our vehicle view took its heading from that pawn, so the mouse WAS turning the view there.
  VehicleFrame(): a seat's view rides the base vehicle (ONSWeaponPawn.VehicleBase), a stationary turret the heading
  at entry. Debug VRMouseTurn <aTurn> (2 s, through our PlayerTurreting.PlayerMove). Mock: Goliath top turret and
  Hellbender side gun - mouse spins the gun, head yaw constant.
- Gaze-only vehicle aim (user: "feels worse; all turrets aim with gaze ONLY, mouse does nothing; Manta rotates
  toward gaze; rubber-band guns keep lagging and aim where the gun points"): mouse yaw aim and AimAlongVehicle
  removed. In a vehicle UpdateRotation (PlayerDriving) and our PlayerTurreting.PlayerMove ignore aTurn/aLookUp and
  set the controller to the gaze (GazeVehicleRotation; relative seats converted), so bFollowLookDir vehicles (Manta,
  Raptor) steer toward the gaze; guns aim along the gaze view. InstantTurretSpeed default 0 (instant, as UT);
  TurretSpeed 0.6 kept for the rate-limited ones. First mock: with the view locked to the Manta a 60-degree head turn
  led it forever (spun ~77 deg/s). Now VehicleViewYaw lets the view follow bFollowLookDir vehicles at
  GazeSteerFollow (0.3/s): the Manta faces the gaze within ~1 s, then turns ~17 deg/s while the head stays turned.
- Own body on turrets (user: "on a static turret (ONS-RedPlanet home base) there's a player model in the view"):
  gunner seats and turrets (ONSWeaponPawn: bDrawDriverInTP) draw the driver attached to the gun; UT's 2D camera
  sits ahead of it, but our view keeps the entry heading while the gun turns with the gaze, so the body swung into
  view. RenderTexture now hides the vehicle's Driver (+ its attachments and held gun model) just for the eye
  portals (bHidden toggled around DrawPortal; others still see it). VREnterVehicle <Part> can now pick turret seats
  (ONSManualGunPawn). Mock, ONS-RedPlanet manual gun: gun turned toward the gaze, no body in view.
- Behind view in vehicles/turrets (user: "behindview doesn't work for turrets and any vehicles"): two causes of
  my own - the BehindView override turned every behind-view request in a vehicle into a seat change (meant for
  Vehicle.NextWeapon's chase-camera switch; the wheel reaches our NextWeapon exec directly, so it's gone), and
  PlayerTick forced first person whenever bBehindView was set (meant only for entry: ONS vehicles start in behind
  view; the entry block still does that). Now UpdateHeadWorld's vehicle branch has a chase camera (VehicleChaseCam:
  GetCameraLocationStart + TPCamLookat along the view heading + TPCamWorldOffset, back TPCamDistance at
  VehicleBehindPitch, traced); PlayerCalcView keeps the VR view in vehicles in behind view (gaze aim); the driver
  and the vehicle mesh show in behind view. Mock: Goliath and ONS-RedPlanet manual gun, camera behind/above.
- "Player model not visible on a turret in behind view": checked, not a bug. On ONS-RedPlanet's base turret
  (ONSManualGunPawn) the driver is drawn every frame (LastRenderTime fresh; flags visible, any character, stock Jakob
  too), but a marker at Driver.Location sits inside the top of the turret housing: these turrets enclose the gunner,
  as in 2D. (In first person our eyes were inside that shell, which is why the body filled the view before.)
  Tools: `set UT2004VR.VRPlayerController <var> <value>` works from TestExec (engine command), and
  `um win shot` of the main window shows the same VR camera in vehicle behind view.
- Startup off-centre (user: "intro and startup screens often appear left/right/up/down; I launch the game, then
  pick up the headset; SteamVR Home always uses my seated calibration"): the intro's free-view anchor (CineAnchor,
  CineRefYaw) and the main-menu panel were taken from the headset's first pose - often lying on the desk. The proxy
  now sends SteamVR's seated calibration (GetSeatedZeroPoseToStandingAbsoluteTrackingPose, "Z" with the static
  packets); the intro anchors on it (head pose only as a fallback), and the standalone panel's first placement uses
  it. The look-away recentre (30 deg for 1.5 s) now only runs while the headset is worn and then follows the head.
  Mock (no HMD, no calibration): unchanged fallback, intro and menu fine. Needs the real headset to verify.
- Startup off-centre, round 2 (user: "still off"): the user's logs showed (1) the intro anchored on the first head
  pose before the proxy's "Z" arrived (static packets go out every 60 frames); (2) the calibration's position is not
  where the user sits (panel placed at 0.94 m height with the head at 1.60 m, ~0.5 m off sideways). Now the
  direction comes from the seated calibration and the position from the head: the intro waits up to 1.5 s for "Z",
  then re-anchors its position at the head once WornTime > 0.5 (worn + moving); the proxy panel faces the
  calibration and sits in front of the head, placed again when the headset goes on. The proxy's worn flag now also
  needs head motion in the last 1.5 s (WMR reported worn=1 for a headset on the desk).
- Curved, mipmapped 2D panels (user: "a slight curvature like SteamVR Home's popups: easier to read, fewer moire-like
  artifacts"): the panel is now a strip of 24 columns on a vertical cylinder (PanelPoint; radius = distance /
  PanelCurvature, default 0.6 -> 1.83 m at 1.1 m), the cursor sits on it, and the controller pointer hits the cylinder
  (far root from inside). The moire: the 1920x1080 window copy was sampled down without mips; the panel texture is now
  D3DUSAGE_AUTOGENMIPMAP (GenerateMipSubLevels after each copy) with anisotropic x8 + linear mip filtering
  (fallback: the old single level). Mock: in-game Esc menu curved, mipmaps on.
- Redeemer reticle (user: "the original has a red crosshair in alt-fire mode"): DrawRedeemerReticle while IsRiding:
  a red dotted ring + gapped cross (dark outline) at the point the warhead's flight line hits (trace 20000 uu), drawn
  into both eyes at that depth. Mock (DM-Antalus, 30-degree launch): centred during the flight, gone after the blast.
- Redeemer window (user: "the original narrows the view to a round glass with red markings and glow; a window at the
  projectile's tip"): DrawRedeemerWindow, in each eye: a window RedeemerWindowDist (0.6 m) ahead along the flight,
  fixed to the warhead (so it has stereo depth and head turns show its rim), RedeemerWindowDeg (80) wide, black around
  it. Inside it UT's own overlay materials, drawn as Warhead.DrawHUD's square case (RDM_OuterEdge/InnerScope quadrants
  mirrored with negative UL, RDM_OuterScope, the RDM_Altitude bars); a generated Porthole.tga is the fallback. Our
  red reticle is off with the window (bRedeemerReticle). Mock screenshots (ONS-Torlan, 15-degree launch; Antalus
  spawns in a cave where the warhead hits the ceiling at once): round view, red rim, centre circle and brackets,
  altitude bars - as in the user's 2D screenshot.
- Redeemer red reticle removed (user: the window with UT's own markings is enough).
- Inherited grips (user: list everything you can carry, then "let's try that"): Grips/KBMGrips matched the exact
  class name, so variants got no offset. FindGrip now takes the exact entry, else the nearest ancestor that has one
  (ClassIsChildOf; entry classes loaded by name from the weapon's own package, XWeapons, Onslaught, UTClassic,
  OnslaughtFull; cached per weapon class and mode, cleared by VRGrip/VRGripReset/LoadTuning). UnrealScript has no
  Class.SuperField, hence the lookup by name. VRGripInfo says "(from X)". Mock (keyboard mode): ClassicShockRifle,
  SuperShockRifle, ZoomSuperShockRifle -> ShockRifle; Classic Flak/Minigun/Rocket/Bio -> theirs;
  ClassicSniperRifle and ONSAVRiL: none (not subclasses of a tuned gun).
- Cicada (ONSDualAttackCraft, OnslaughtBP) invisible when driving (user report): UT hides it in first person
  (bDrawMeshInFP False), it had no VehSeats entry, and its camera is at its centre (FPCamPos 0) inside the hull, where
  the faces point away and are culled even when drawn. Now any vehicle UT hides in first person is drawn around you
  unless its seat says hide (also seats with neither flag), and BuiltInSeat gives vehicles without an entry a
  fallback seat: Cicada (80,0,40) - forward and up, nose and rotor arms ahead (mock: 0,0,0 looks at its belly, higher
  puts the rotor blades in the way). VRSeat still makes your own.
- Keyboard-mode scope lens 20% further (ScopeKBMDistance 0.45 -> 0.54 m) and 0.21 m wide (was 0.17), so it looks the same size or a touch bigger (user request).
- Keyboard-mode scope lens (user: "should not follow head rotation; turn with the gun about the vertical axis; no change about horizontal axes"): ScopeLensW is now along the gun's flattened heading at eye height, and the scope picture's up is world up (was the head's up). Controller mode unchanged (lens on the gun). Mock, head pitched 20 / rolled 15: lens below the view centre at eye height, picture level.
- Scope lens as a 3D object (user: "the frame turns when I gaze left/right/up/down; it should keep facing the aiming
  point"): the canvas lens was a disc drawn upright in each eye, i.e. always facing you - looking away made it turn
  toward your gaze. Now two VRLensActor discs in the scene (picture: ScopeMat; rim: ScopeRing as FinalBlend), facing
  along the aim, top level (keyboard mode) or the gun's top (controller mode); the scope picture uses the same frame.
  Reverts cc6416e's eye-height placement (the user meant the frame, not the picture). The disc is a generated
  Unreal-1 vertex mesh (Models/VRLensDisc_a/_d.3d, #exec MESH IMPORT). Found: UCC reads the packed vertex values as
  is (no /8, /4 - the first try came out 800x400 uu), and the two-sided poly flag is ignored (back faces culled: the
  disc rendered every frame yet stayed invisible) - the mesh now has both windings. Mock (head pitched 20/rolled 15):
  lens level with the world, turned on screen accordingly, rim and reticle drawn.
- Menu panel closer: PanelDistance 1.1 -> 0.95 m (user: "settings and other 2D screens a bit closer"; width kept, so it also looks ~15% bigger).
- Spectator hint (user: "spectator mode shows Click to join, click does nothing; join is via Esc"): our VR HUD showed the join hint whenever there was no pawn. Spectating (state Spectating / bOnlySpectator) now reads "Spectating / Click: next player   Esc menu: join" (trigger in controller mode); "Click to join" only while waiting to join. Mock (?SpectatorOnly=1): shown.
- Single Player 2D flicker before 3D (user report): ladder matches start without the VR mutator; until VRConsole's
  reload (0.5 s in) the console announced "M 2" (a game without VR -> the flat window on the big screen). Now
  WillReloadWithVR -> "M 1" (dark room). Also the proxy showed whatever eye targets the last VR level left once the
  menus' standalone timed out during a level load (stale/half-overwritten frames): game eyes are now only shown while
  "M 0" keeps coming (2 s). M 0 moved to VRMirrorInteraction.PostRender (every 30 frames): the controller doesn't
  tick while paused, and the first try turned the paused Esc menu's background into the dark room. Mock: no-VR start
  -> dark room, reload, VR; paused Esc menu keeps the game behind the panel.
- Game messages in VR (user: "first blood, You picked up a Flak Cannon... should be visible in 3D, same fonts"):
  HudBase keeps two queues (LocalMessages: special messages; TextMessages: kill/chat lines) but only draws them in
  its 2D PostRender, which VRHUD skips in VR - so the queues also never aged. VRHUD.DrawVRMessages ages them once a
  frame and draws them into each eye on a virtual screen whose corners are the VR HUD's (HudPoint, HUD depth), with
  each class's GetPos pivot/stacking, GetColor, fades and UT's font steps for that screen's width in eye pixels
  (~1565 px at 2688/102 deg) plus VRMessageFontBoost=2 (UT's 2D sizes are ~0.5 deg tall here, too small in the
  headset). It lives in VRHUD because reading the 576-byte LocalMessages array from another class is a truncated
  context expression ("Variable is too large"). Debug: VRTestMessages. Not tested yet (the user was playing).
- Whole HUD a bit lower (user request): new HudLower=0.05 shifts every HudPoint/HudText point down (items, messages, scoreboard, hints); the user's own HudTopUp/HudBottomUp stay as they set them. At their HudSpread 1.9 / HudDistance 2.5 that is 9.5 cm, about 2.2 degrees. Built, not tested in the headset.
- Match clock in the VR HUD (user request): top centre at HudTopUp, UT's clock icon (HUD 150,356 34x33) and digits with UT's timer colon (495,91 8x21); RemainingTime with a time limit, else ElapsedTime, h:mm:ss past an hour (HudCDeathMatch.DrawTimer). bVRClock. HudDigits now goes through HudDigitString (':' and '-').
  Mock (?TimeLimit=20, user's HudSpread 1.9): clock '19:00' top centre; VRTestMessages shows Double Kill (upper middle), first blood and the Flak pickup (lower middle), kill/chat lines lower left in their colours. The first-blood line and the longest console lines come close at the lower left-centre: the VR HUD rectangle is nearly square (16:9 in 2D), so left-anchored lines reach further toward the centre. Mock eyes are 672 px, so the headset's font sizes differ.
- Startup flashing in the dark room (user report, proxy log: "VR game eyes up" / "standalone view: menus" alternating
  ~3x a second from the moment the main menu opened): a regression from 008f83c. The startup intro (NvidiaLogo,
  CinematicGame) runs with a VRPlayerController; VRMirrorInteraction outlives the level and still held that
  controller, which still looked VR-active, so its "M 0" every 30 frames fought the console's "M 1". It now lets go
  of a controller that is no longer the viewport's. Mock (new MockDemo=9: worn, head 0 / +40 / -40 deg): intro ->
  one "standalone view: menus", no flips.
- "Turn ~40 deg and the screen disappears" (same report): the main-menu panel followed you after 1.5 s at > 30 deg
  away (607a27b, from before the seated-calibration placement), so looking back it was gone. Now off by default,
  PanelFollowDeg in UT2004VR_proxy.ini (30 = the old behaviour). Mock MockDemo=9: the panel stays put through the turns.
- Main-menu panel still vanished at ~40 deg (user, after the follow fix; their log: the panel was placed once and
  never moved): DrawPanelInEye skipped the whole panel for the frame when any strip vertex was behind the eye. The
  1.6 m curved panel's far edge goes behind the eye plane at a ~40 deg turn. Now only the columns with a vertex
  behind the eye are left out (they're outside the view). Mock MockDemo=9 (panel placed straight, head then 40 and
  55 deg): the panel stays in view at the side.
- Scoreboard like the original (user: "fonts, layout, transparency"): instead of porting each game type's scoreboard
  to ScriptedTexture drawing, the headset now shows UT's own. While it's up VRHUD sends "S 1" and every 8th frame
  pair draws ScoreBoard.DrawScoreboard alone on black, then on white, with a 2-pixel marker at the bottom right (the
  top left gets VRMirrorInteraction's 1x1 eye tiles). The proxy reads the marker (2x1 StretchRect + readback),
  copies those frames into two mipmapped textures and puts the previous window picture back before Present (the
  desktop never sees them: an 8 s window recording had steady brightness in all 248 frames). A ps_2_0 shader
  compiled at runtime with d3dcompiler_47 makes alpha = 1 - avg(white - black), colour = black (premultiplied),
  blended ONE/INVSRCALPHA onto a curved panel placed in front of you when it comes up (ScoreboardDistance 1.0 m,
  ScoreboardWidth 1.5 m). The VR HUD hides under it as in 2D (messages only if ScoreBoard.bDisplayMessages). The
  desktop mirror shows the panel from the eye (drawing the 2D one too doubled it). Mock: DM (row boxes, header,
  frag limit / time line) and Onslaught (red/blue team boxes, team icons, bot locations) both as in 2D.
- Keyboard-mode gun off to the left after putting the headset on mid-match (user: "started in keyboard mode from the
  window, picked up the headset later, gun pointing left, not at my gaze"; happened before too). Their log: "chair
  forward" (the room direction the mouse-aimed gun counts as straight ahead) was measured twice with the head at
  0.83 m, i.e. the headset on the desk: the measurement accepted the headset's worn flag, which WMR reports on the
  desk too. Now: it only counts while the head actually moves (within 20 s), and its yaw comes from SteamVR's
  seated calibration ("Z") when there is one, like the menu panel and the intro; only the natural head pitch comes
  from the gaze. VRRecenter still takes the yaw from your gaze. Mock: still head (MockDemo=2, a desk headset) ->
  never measured; moving head -> "chair forward yaw 1885 (level gaze)". The seated-calibration branch isn't covered
  by mock (no seated pose there).
- Clock seconds stuck at :00 (user report): UnrealScript % returns a float, so Secs % 60 printed as "39.00" and Right(.., 2) took "00". int() it (also in the drawn scoreboard header). Mock: 19:46, 19:42, 19:39 in successive dumps.
- Clock digits at the frag-delta size (Small, icon scaled with it), user request.
- Desktop window cropped around the HUD (user: "the HUD isn't centred in the window; depending on the aspect the
  bottom row is cut off while the top row is well below the top"): the crop was symmetric around straight ahead,
  but the HUD sits lower (the user's HudTopUp 0.44 / HudBottomUp -0.65, plus HudLower). MirrorFitHud: the HUD
  rectangle (+-0.62 wide, top/bottom rows, MirrorHudMargin 0.1) in the mirrored eye's tangents, shifted by half
  the IPD at HudDistance, centred, grown to the window's aspect, clamped to the rendered eye. bMirrorFitHud.
  Mock (1680x1050): top row near the top edge, health/ammo near the bottom, equal margins left and right.
- HUD digits and icons 15% smaller (user: "slightly smaller"): HudSize=0.85 scales Big/Small/Icon (clock included). Messages keep their own size (VRMessageFontBoost). Mock: all items smaller, layout unchanged.
- 2026-10-18, before publishing (private GitHub repo): the repository starts over with one commit (the user's choice);
  commit IDs quoted above refer to the earlier local history (kept locally as a bundle).
- Spectator mode like the original (user: "the panel at the bottom with the player name and how to switch could
  float in 3D"): the scoreboard capture is now an overlay capture of kind 1 (scoreboard) or 2 (UT's
  HudCDeathMatch.DrawSpectatingHud: SquareBoxA bar in yellow, LMS logo, Now Viewing / name / score, tag line).
  "S <kind> <top>" tells the proxy the window share to show (the bar: from its top edge, computed from the same
  fonts as UT's layout); the proxy crops the panel to that strip and places the bar SpectatorBarDrop 0.3 m below
  eye level at 1.0 m, 1.3 m wide. Our own "Spectating / Click: next player" text and the VR clock are off under it.
- Spectator clicks did nothing (also the user's earlier "click does nothing" report): neither VRPlayerController's
  global Fire nor PlayerController's Spectating.Fire ran from the Fire alias while spectating (a direct
  ServerViewNextPlayer worked). Now PlayerTick reads the buttons while spectating (bFire/bAltFire; the trigger via
  bBtnFire in controller mode, which VRWeaponInput doesn't map without a pawn): fire -> ServerViewNextPlayer, alt ->
  ServerViewSelf, with a 0.3 s guard against the exec path seeing the same click. Debug: VRTapFire, VRSpecNext.
  Mock (?SpectatorOnly=1, 3 bots): before - "Press Fire to View a different Player" bar; VRTapFire -> "spectating
  xPawn2", bar shows Now Viewing / Divisor / score 1 under the chase view.
- Typing prompt in VR (user: "T opens say, visible in the window but not in 3D"): HUD.PostRender draws DrawTypingPrompt on the window only. VRHUD.DrawVRMessages now draws the same line ("(>" Say ... chr(4) cursor, ConsoleColor) in the free line under the console messages, also under the original scoreboard. Mock ("talk"): "(> Say _" above the health row.
- Menu panel edges (user: "the cropping of some in-game menus and dialogs leaves their background visible at the
  edges"): the crop was the active page's bounds plus a 1% margin, which showed the black around an in-game menu as
  an uneven frame and, for dialogs (UT2K4QuitPage: a full-width strip), the darkened menu behind as strips at the
  top and bottom. Now exactly the page bounds, and in a game (not the main menus' dark room or the big screen) a
  ps_2_0 key shader makes the pure black around the menu see-through (alpha 0 below ~2/255, 1 from ~6/255), so the
  bevelled corners show the game. The cursor and beam are drawn without it. CompilePS shared with the scoreboard
  shader. Mock: Esc menu and "Are you sure you wish to quit?" without a frame, corners transparent.
- Menu edges, part 2 (user: "still parts of the background at the edges, especially the bottom pixels, Esc menu
  and Exit dialog"): the page art ends in small corner tabs with gaps between them, and a dialog's gaps showed the
  greyed page under it (in the main menus also the background art), which no key can remove. VRMenu now draws a
  dialog alone while it is on top (its GUIPage.bRenderWorld off, put back after; G.Count() > 1) and says so in "R
  ... 1"; the proxy keys a dialog in the main menus too. Mock: in-game quit dialog alone in the window, eyes keep
  rendering behind the panel; main-menu quit dialog (debug VRConsole.VROpenMenu) alone in the dark room, clean edges.
- OldUnreal Patch 3374 Preview 23 in the lab (2026-10-19, user's choice: lab only, C:\UnrealTournament2004 stays on
  Preview 9). Preview 9 = build 2026-02-07; Preview 23 = build 2026-07-18 (d1b145e1), from the GitHub release
  OldUnreal-UT2004Patch3374-Windows-094b94dc.zip (sha256 fd81fa55...4bd3). It holds no d3d9.dll and no user inis
  (only Build.ini, Default*.ini). The 525 lab files it overwrote are in C:\UT2004-VRLab-backup-preview9-20261019,
  with ADDED_BY_PATCH.txt listing its 1052 new files (to undo: copy the backup back, delete those). UT2004VR
  rebuilt clean. Mock: AS-Convoy as UT2k4Assault.ASGameInfo + VR mutator + 4 bots -> ASGameInfo::BeginRound, no
  crash, PlayerWalking in VR, clean exit; DM scoreboard capture and the menu panel/key shader still work.
