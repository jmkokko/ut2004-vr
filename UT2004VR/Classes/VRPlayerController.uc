//=============================================================================
// VRPlayerController: Half-Life: Alyx-style VR camera and locomotion for UT2004.
//
// - The camera follows the tracked head, and the pawn's capsule follows the head
//   (room-scale walking moves the pawn with collision, like Alyx).
// - Left stick: smooth locomotion, relative to the head or the left hand (config).
// - Right stick left/right: snap turn (or smooth turn). Right stick forward: aim the
//   teleport arc, release to blink there.
// - Jump / crouch buttons, and physical crouching.
// Falls back to the normal UT2004 controls whenever no pose packets arrive.
//=============================================================================
class VRPlayerController extends xPlayer
	dependson(VRTuning)
	config(UT2004VR);

// ---- config (UT2004VR.ini, [UT2004VR.VRPlayerController]) ----
var config float UUPerMeter;        // world scale; UT2004 is ~52.5 uu per meter
var config bool  bHandRelativeMove; // Alyx "hand" vs "head" oriented continuous locomotion
var config bool  bGazeHeading;      // move along a body heading that turns toward the gaze while moving forward
var config float HeadingTurnRate;   // that turn: rate per second per unit of forward stick, proportional to the angle
var bool  bKeyboardMouse;           // keyboard/mouse mode: WASD + mouse like flat UT, headset = freelook, gun fixed to the body (saved in [VRTuning] only)
var config vector KBMGunOffset;     // that gun's handle relative to the chest point, in aim axes (uu)
var config float KBMChestBelowEyes; // chest point: this far (m) below the stock eye height
var config float GunLagTime;        // keyboard/mouse: the gun eases back to its place over this many seconds when you move
var config float GunLagMax;         // ... lagging at most this far (m); 0 = off
var vector GunLag, GunLagRaw, GunLagHead;
var config float GunLagSmooth;      // ... easing in and out over this many seconds
var config int   NeckModelMode;     // the eyes' turning arc: 2 while the headset tracks rotation only, 1 always, 0 never
var config float NeckForward, NeckUp; // the eyes from the neck pivot (m)
var config float NeckBlendTime;     // ... blended in / out over this many seconds
var bool   bNeckModel;
var float  NeckBlend, NeckBlendAt;
var vector BodyHeadPos;              // the head position without the turning arc (playspace m): the keyboard gun's anchor
var vector VRBodyWorld;              // ... in the world
var vector GunTargetPawnLoc;
var float LagTraceUntil;            // debug: VRLagTrace
var float BeamGap;                  // debug: VRBeamLog        // Pawn.Location when GunTarget (the muzzle) was placed
var float GunLagAt;
var config bool  bSteerByGaze;      // seated head steering: walking forward while looking aside turns the view itself
var config float SteerGain;         // turn speed in deg/s per degree of look angle (times forward stick)
var config float SteerDeadzone;     // degrees of look angle that do not steer
var config float SteerMaxDegPerSec;
var int   ChairYaw;                 // playspace yaw of the chair's forward (set at calibration / recenter)
var int   ChairPitch;               // your natural head pitch at that moment = "level" in keyboard/mouse mode
var int   ChairCount;
var bool  bChairMeasured;           // chair forward/pitch taken (first calibration, or recenter); respawns keep it
var bool  bChairYawValid;
var config bool  bSmoothTurn;
var config int   SnapTurnDegrees;
var config float SmoothTurnDegPerSec;
var config float MoveSpeedScale;    // fraction of UT's GroundSpeed at full stick (UT is fast for VR)
var config bool  bTeleport;
var config float TeleportSpeed;     // arc launch speed, uu/s
var config float TeleportMaxDist;
var config float CrouchHeadMeters;  // physical crouch threshold (head height above floor)
var config bool  bVignette;
var config bool  bVRHud;            // head-locked HUD (health, shield, adrenaline, ammo, score) at a real 3D depth
var config float HudDistance;       // meters in front of the eyes
var config float HudSpread;         // scales how far the items sit from the centre of view
var config float HudTopUp;          // top row height (m at HudDistance, before HudSpread)
var config float HudSize;           // HUD digits and icons, relative to the original size
var config float HudLower;          // moves the whole HUD (items, messages, scoreboard) down by this much
var config float HudBottomUp;       // bottom row height (negative = below the centre)
var Font HudBig, HudSmall;
var config bool  bWeapons;          // false = travel only (no guns)
var config vector GunOffset;        // gun's visual centre relative to the controller tip, in aim space (uu)
var config int   GunPitchOffset;
var config array<string> FlipGuns;  // exceptions to the up rule (VRGunFlip): roll these 180
var array<VRTuning.GripOfs> KBMGrips;   // keyboard/mouse mode's own per-weapon offsets (VRGrip in that mode)
var array<VRTuning.VehSeat> VehSeats;   // per-vehicle seat offset and mesh (VRSeat, VRSeatMesh)
var class<Weapon> GripCacheClass;   // FindGrip's last answer (cleared when the grips change)
var bool     bGripCacheKBM;
var int      GripCacheIdx;
var array<VRTuning.GripOfs> Grips;  // per-weapon handle offsets (VRGrip), persisted in VRTuning    // tilt the aim down/up relative to the controller (rotator units)
var config float GunScale;          // first-person meshes are ~1.7x real size (they sit next to the camera)
var config float MuzzleForward;
var config bool  bScope;            // zoom (Lightning Gun, Sniper alt-fire): a magnified picture in a round lens
var config float ScopeDiameter;     // controller mode: lens size (m), held on the gun above your hand
var config vector ScopeOffset;      // controller mode: lens centre from the gun's handle (m; forward, right, up)
var config float ScopeKBMDiameter;  // keyboard mode: lens size (m), in the middle of your aim
var config float ScopeKBMDistance;  // keyboard mode: how far ahead of your eyes (m)
var config float ScopeMinZoom;      // magnification at the start of a zoom (UT's own zoom raises it)
var config int   ScopeRes;          // the scope's render target, pixels
var ScriptedTexture ScopeTex;
var VRLensActor LensPic, LensRim;   // the lens in the scene (picture, rim)
var Material ScopeMat;              // the scope picture, cut round (ScopeMask)
var bool     bScopeOn;
var float    LastAdjustView;    // UT's AdjustView (zoom, FOV recovery) last ran
var float    AltHoldUntil;
var float    DebugStickX, DebugStickY, DebugStickUntil;   // debug: VRStick
var float    NextScopeLog;      // debug: VRAltHold
var vector   ScopeCamLoc, ScopeLensW;
var rotator  ScopeCamRot;
var float    ScopeLensR, ScopeViewFOV;
var float    ScopeReticleRoll;          // radians: the gun's up in the scope picture, clockwise from the picture's up
var array<Actor> ScopeHidden;           // hidden during the scope render (the guns and their effects)
var config float BehindDistance;    // behind view on foot (F): the camera this far behind you (m)...
var config float BehindHeight;      // ...and this far above your eyes (m)...
var config float BehindRight;       // ...and this far to the right (m; over the shoulder, so the gun and laser show)
var bool     bTPGun;                // behind view: the gun hangs in the character's hand (UT's attachment)
var config float FighterSteer;      // controller mode: right stick -> Assault space fighter pitch / yaw rate, as the mouse (negative: inverted pitch)
var config float RedeemerSteer;     // controller mode: right stick -> guided Redeemer turn rate (negative: inverted pitch)
var config bool  bRedeemerRoll;     // ride the warhead's banking too (off: the horizon only pitches and turns)
var config bool  bRedeemerWindow;   // ride behind a round window at the warhead's tip (2D's scope overlay, in 3D)
var config float RedeemerWindowDeg; // how wide the window looks from your seat (degrees)
var config float RedeemerWindowDist;// how far ahead of you it is (m)
var Pawn     LastWarhead;           // riding a guided Redeemer: the head when it launched, and the reference heading
var vector   WarAnchor;
var vector   SeatZeroPos, SeatZeroF;    // SteamVR's seated calibration ("Z" from the proxy)
var bool     bSeatZero;
var bool     bChairFromGaze;
var bool     bSpecFireHeld, bSpecAltHeld;   // spectating: the buttons last tick
var float    SpecSwitchTime, TapFireUntil;           // the next chair forward comes from the gaze (recenter), not the seated calibration
var bool     bCinePosWorn;
var int      CineYawSrc;   // the free view's heading: 0 the headset at startup, 1 the seated calibration, 2 your head once worn, 3 your chair
var float    CineWaitStart;
var int      TurretEntryYaw;
var config float VehicleBehindPitch;  // behind view in a vehicle: the camera looks down this much (deg)...
var config float VehicleBehindScale;  // ...from UT's chase distance times this
var config float GazeSteerFollow;   // Manta/Raptor (they turn toward your gaze): how fast the view follows the vehicle (1/s)
var float    VehViewYaw, LastViewYawT;        // a turret with no vehicle under it: your heading when you got on
var float    DebugTurn, DebugTurnUntil;   // debug: VRMouseTurn
var int      WarRefYaw;
var config float TurretSpeed;          // vehicle guns that turn at a set rate (Goliath cannon): that rate times this
var config float InstantTurretSpeed;   // guns UT turns instantly to the view (turrets, Hellbender): turns/s (0: instant, as UT)
var array<ONSWeapon> TunedGuns;        // vehicle guns slowed for VR, with their own values to put back
var array<float> TunedRPS;
var array<byte>  TunedInstant;
var config bool  bVehicleLaser;     // in vehicles: the laser from the gun's muzzle (else a crosshair at its hit point)
var config bool  bLaser;            // aiming laser from the muzzle to whatever the gun points at
var config float LaserRange;
var config float LaserDotSize;      // dot size, as a fraction of the distance (constant angular size)
var config float LaserBrightness;   // 0..1 (additive, so this is its translucency)
var config float LaserWidth;
var config float LaserFadeIn;       // seconds to fade back in after firing stops (hidden while firing)
var float LaserLastFire;
var VRLaser Laser;
var VRArcDot LaserDot;     // where shots start, uu in front of the controller tip
var bool  bBtnFire, bBtnAlt, bBtnNext, bBtnPrev, bBtnDodge, bOldDodge, bBtnScores, bOldScores;
var config bool bVROriginalHud;     // the headset shows the game type's own HUD (captured), not the drawn VR HUD items
var config float OriginalHudScale;  // ... that HUD's width, relative to the VR HUD's (its corners at +-0.62 x HudSpread)
var config float ASTurretFollow;    // Assault turrets follow your gaze over this many seconds
var VRGameMarkers Markers;          // the game types' world-pointing markers (objectives...), drawn in 3D
var config bool bVRScoreboardOriginal; // the headset shows UT's own scoreboard (captured by the proxy), not the drawn one
var bool  bShowVRScores;            // scoreboard panel in the VR HUD (left X, or VRScores)
var float MenuBtnDownTime;          // left Y: short press = Esc, hold = recenter
var bool  bMenuBtnLong, bMenuBtnSkip;
var bool  bCrouchSuppressed;        // a jump/dodge while holding crouch stands you up until crouch is released
var Material ScoresBack;
var Font ScoresFont;
var int ScoresFontFor;               // eye texture width ScoresFont was picked for
var config float ScoresWidthDeg;    // scoreboard panel width (degrees); the font size follows from it
var config bool  bVRClock;          // match clock at the top centre of the VR HUD
var config bool  bVRMessages;       // UT's game messages (pickups, first blood, sprees, kills, chat) in the VR HUD
var config int   VRMessageFontBoost; // message fonts this many sizes bigger than UT's choice for the same screen
var byte  PendingStandMove;        // 1 jump, 2 dodge: pressed while crouched, fires once standing
var EDoubleClickDir PendingDodge;
var float PendingStandUntil;
var int   BodyYaw;                  // body heading (world yaw) the left stick moves along
var bool  bBodyYawValid;
var bool  bOldFire, bOldAlt, bOldNext, bOldPrev;
var Weapon ShownWeapon;
var float  ShownSince;
// per-attachment-class barrel calibration, measured once at rest and cached
struct GunCal
{
	var class<Actor> Cls;
	var vector TipL;            // muzzle (tip bone) in attachment space
	var vector GripL;           // the hand bone the model normally hangs from, in attachment space
	var vector Xb, Yb, Zb;      // barrel frame in attachment space
};
var array<GunCal> GunCals;
var int    CurCal;              // index into GunCals for the shown gun, -1 = not calibrated yet
var bool   bGunCalibrated;
var vector GunTarget;           // world point where the muzzle sits this tick
var vector GunHandleW, GunHandW; // debug: the handle point and the hand this tick
var Actor  GunModel;            // what is drawn in the hand (third-person model; complete and real-size)
// recoil: each shot kicks the gun back and its muzzle up, and it springs back. Only the model moves: shots still go
// along your aim. The first-person weapons' fire animations (UT's kick) are on models with arms and missing backs,
// so the held third-person model gets this one instead.
struct RecoilKick
{
	var name  Fire;             // the fire mode's class (or a parent): the first match in the list counts
	var float Back;             // cm
	var float Up;               // degrees
};
var array<RecoilKick> Recoils;
var config float RecoilScale;   // 0 = off
var config float RecoilReturn;  // seconds the gun takes to spring most of the way back
var float RecoilAmt, RecoilShown, RecoilBack, RecoilUp, RecoilAt;
var float RecoilNFT[2];          // each fire mode's NextFireTime: it moves on with every shot
var Weapon RecoilWeapon;
var config bool  bAutoHeight;       // seated-friendly: map your head height at spawn/recenter to StandEyeMeters
var config float StandEyeMeters;
var config bool  bMatchGameHeight;   // eyes at the pawn's stock eye height (UT2004: 44 + 38 = 82 uu), whatever your real height
var config float EyeHeightBonus;     // uu added to that (VRHeight)
var float HeightOffset;
var config bool  bSeatedAutoLevel;   // seated: slowly re-level the eye height (posture changes, tracking drift)
var config float AutoLevelSeconds;   // time constant of that re-levelling
var bool  bSeatedLevel;              // active (seated player, matched height)
var float RawHeadZ;                  // head height before the offset (m)
var float SlowHeadZ;                 // its slow average
var float CalibSum;                  // averaging window at calibration
var vector CalibFwdSum;              // head forward summed over the same window (the chair's forward)
var int   CalibCount;
var bool  bNeedHeight;
var bool  bForceHeight;      // recenter: always put the eyes at StandEyeMeters
var float WornTime, LastPacketTimeH;
var vector MotionRefPos, MotionRefF;   // the head pose half a second ago
var float MotionRefTime, LastHeadMotion;
var bool  bOldMenu;
var config bool  bDebugLog;
var config string TestExec;         // debug: console command run once ~3 s after spawn
var bool bTestExecDone;
var string TestExecNext;
var string TestExecCarry;           // the rest of a TestExec sequence across a level change             // TestExec "a|b|c": the rest, one command every ~90 frames (works while paused)
var int TestExecFrames;

var config bool  bCalib;
var config bool  bCalibGun;         // debug: mark the muzzle and candidate barrel lines in the eye images            // projection test: 3D markers at known angles + 2D boxes where the math predicts them
var VRArcDot CalibDots[5];
var vector CalibPts[5];
var vector CalibOrigin;
var rotator CalibRot;         // once a second: pawn, playspace and input state to UT2004.log
var float NextDebugLog;
var float NextGunEyeLog;

// ---- tracking state (from VRLink) ----
var VRLink Link;
var ScriptedTexture EyeTex[2];  // one render target per eye: own viewport, so DrawPortal's projection is square
var int EyeTexW, EyeTexH;
var VRMirrorInteraction MirrorIA;
var bool  bMenuOpen;                 // UT's menu (GUI) is up: the proxy shows it as a panel in the headset
var float WinW, WinH;                // desktop window (canvas) size, from VRHUD
var VRMenu Menu;
var float NextCrossLog;
var Vehicle LastVehicle;             // in a vehicle: the head when you got in, and the reference heading
var vector VehAnchor;
var int   VehRefYaw;
var int LastLoggedPitch;
var bool bVRGoNear;
var float PitchLogUntil;
var bool  bCineAnchored;             // cinematic (UT's intro): head position/heading when it started
var vector CineAnchor;
var int   CineRefYaw;
var vector CineCamLoc;               // the cinematic camera, as UT's own PlayerCalcView places it (Matinee)
var rotator CineCamRot;
var bool  bCineCam;
var float NextCineLog;
var VRCineCam CineCam;
var float NextLinkTry;                     // the menu panel driver (shared with VRConsole)
var int   MirrorEye;                 // from the proxy: 0/1 = mirror that eye in the window, -1 = off
var config bool  bMirrorFitHud;    // desktop window: crop the eye around the VR HUD (centred, all of it visible)
var config float MirrorHudMargin;  // ... with this margin around the HUD's corners (HUD units, like HudTopUp)
var float MirrorHX, MirrorVY;        // mirror half-size in tangents (symmetric around straight ahead)
var float  LastPacketTime;
var int    HeadSeq;
var vector HeadPos, HeadF, HeadU;            // playspace, meters, Unreal axes
var vector HandPos[2], HandF[2], HandU[2];
var byte   bHandOK[2];
var vector EyeOfs[2], EyeF[2], EyeU[2];      // eye-to-head transform
var int    EyeFOV;
var int    EyeW, EyeH;
var float  StickMX, StickMY, StickTX, StickTY;
var bool   bBtnJump, bBtnCrouch, bBtnMenu;
var string TapBtn;                 // debug: VRTapBtn
var float  TapBtnUntil;
var bool   bBtnUse, bOldUse;      // the right stick click: use (enter / leave a vehicle)
var bool   bOldVehJump, bOldVehDodge, bOldVehNext, bOldVehPrev, bOldVehFire, bOldVehAlt;
var bool   bOldJump, bOldCrouch;

// ---- playspace ----
var int    PlayYaw;          // playspace yaw in world (snap/smooth turn)
var vector Anchor;           // playspace point (meters) that sits under the pawn
var bool   bAnchorValid;
var bool   bTurnLatched;
var bool   bNeedSpawnFacing;  // on spawn, turn the playspace to face the most open direction

// ---- teleport ----
var bool   bAiming;
var bool   bTeleportValid;
var vector TeleportTarget;
var float  BlinkUntil;
var VRArcDot ArcDots[32];
var VRArcDot ArcTarget;

// ---- derived per frame ----
var vector VRHeadWorld;
var rotator VRHeadRot;
var float  VRMoveAmount;     // 0..1, drives the comfort vignette

function PostBeginPlay()
{
	Super.PostBeginPlay();
	LoadTuning();
	if ( Level.NetMode != NM_DedicatedServer )
	{
		Link = Spawn(class'VRLink', self);
		if ( Link != None )
			Link.PC = self;
	}
}

function Destroyed()
{
	local int i;
	for ( i = 0; i < 2; i++ )
		if ( EyeTex[i] != None )
		{
			EyeTex[i].Client = None;
			Level.ObjectPool.FreeObject(EyeTex[i]);
			EyeTex[i] = None;
		}
	if ( LensPic != None ) LensPic.Destroy();
	if ( LensRim != None ) LensRim.Destroy();
	if ( ScopeTex != None )
	{
		ScopeTex.Client = None;
		Level.ObjectPool.FreeObject(ScopeTex);
		ScopeTex = None;
	}
	for ( i = 0; i < 32; i++ )
		if ( ArcDots[i] != None )
			ArcDots[i].Destroy();
	if ( ArcTarget != None )
		ArcTarget.Destroy();
	if ( Laser != None )
		Laser.Destroy();
	if ( LaserDot != None )
		LaserDot.Destroy();
	if ( Link != None )
		Link.Destroy();
	Super.Destroyed();
}

event PlayerTick(float DeltaTime)
{
	local vector VStart, VDir, VHit;
	local ONSWeapon VGun;
	local byte VHitB;

	if ( TapFireUntil > 0 && Level.TimeSeconds > TapFireUntil )
	{
		TapFireUntil = 0;
		bFire = 0;
	}
	SpectatorButtons();

	// UT advances zoom in AdjustView, called from Pawn.UpdateEyeHeight on its own movement path; VR movement skips
	// that, so run it here when it didn't run last frame
	if ( Pawn != None && LastAdjustView < Level.TimeSeconds - DeltaTime * 1.5 )
		AdjustView(DeltaTime);
	// the lens discs stay in the scene until hidden: not after death, a weapon change or the end of the zoom
	if ( bScopeOn && (Pawn == None || Vehicle(Pawn) != None || !IsZoomed() || !GunActive()) )
	{
		HideLens();
		bScopeOn = false;
	}
	if ( AltHoldUntil > 0 && Level.TimeSeconds > AltHoldUntil )
	{
		AltHoldUntil = 0;
		bAltFire = 0;
		if ( Pawn != None && Pawn.Weapon != None )
			Pawn.Weapon.ClientStopFire(1);
		Log("UT2004VR: alt-fire released, zoom fov "$FOVAngle, 'UT2004VR');
	}

	// a link that couldn't get its port closes itself (VRLink.TryBind): make a new one
	if ( (Link == None || Link.bDeleteMe) && Level.NetMode != NM_DedicatedServer && Level.TimeSeconds > NextLinkTry )
	{
		NextLinkTry = Level.TimeSeconds + 0.5;
		Link = Spawn(class'VRLink', self);
		if ( Link != None )
			Link.PC = self;
	}
	if ( Link != None && !Link.bDeleteMe )
		Link.Drain();
	UpdateMenuState();
	VRButtonsTick();
	// dead: the trigger respawns (VRPlayerMove, which reads it otherwise, only runs while alive)
	if ( IsInState('Dead') && VRActive() )
	{
		// the gun model and laser are left over from the dead pawn
		UpdateLaser(false, vect(0,0,0), vect(1,0,0));
		if ( GunModel != None )
			GunModel.bHidden = true;
		if ( (bBtnFire && !bOldFire) || (bBtnAlt && !bOldAlt) )
		{
			bMenuBeforeRespawn = false;   // a mid-game menu can't be used in the headset
			Log("UT2004VR: dead, trigger -> respawn (frozen="$bFrozen$" state="$GetStateName()$")", 'UT2004VR');
			Fire(0);
		}
		bOldFire = bBtnFire;
		bOldAlt = bBtnAlt;
	}
	TuneVehicleGuns();
	if ( Vehicle(Pawn) != None && VRActive() && !bKeyboardMouse )
		VRVehicleButtons();
	if ( Vehicle(Pawn) != None && VRActive() )
	{
		// the hand-held gun stays behind while you drive; the laser comes from the vehicle's gun
		// (not in Assault's vehicles and turrets: their own crosshair is on the aim point, VRGameMarkers)
		if ( bVehicleLaser && ASVehicle(Pawn) == None && !UsingOriginalHud() && VehicleAimTrace(VStart, VDir, VHit, VGun, VHitB) )
			UpdateLaser(true, VStart, VDir, true, VHit, VHitB != 0);
		else
			UpdateLaser(false, vect(0,0,0), vect(1,0,0));
		if ( GunModel != None )
			GunModel.bHidden = true;
		UpdateHeadWorld();
		// the vehicles UT hides in first person (Raptor, Manta): drawn around you if the seat says so; in behind view
		// UT shows them anyway
		if ( bBehindView )
			ShowVehicleMesh(Vehicle(Pawn), true);
		else if ( SeatShowsMesh(Vehicle(Pawn)) )
			ShowVehicleMesh(Vehicle(Pawn), true);
		else if ( SeatHidesMesh(Vehicle(Pawn)) )
			ShowVehicleMesh(Vehicle(Pawn), false);
		else if ( !Vehicle(Pawn).bDrawMeshInFP && ONSWeaponPawn(Pawn) == None )
			ShowVehicleMesh(Vehicle(Pawn), true);   // no seat set: the ones UT hides in first person (Raptor, Cicada) around you too
	}
	if ( IsFreeView() && VRActive() )
	{
		UpdateHeadWorld();
		// the trigger: skips the startup intro to the menu, like a click does; otherwise presses fire (joins the match;
		// in a Matinee intro such as Assault's briefing, UT's Fire skips the scene)
		if ( bBtnFire && !bOldFire )
		{
			if ( IsCinematic() && CinematicGame(Level.Game) != None )
				SkipCinematic();
			else
			{
				Log("UT2004VR: no pawn ("$GetStateName()$"), trigger -> fire", 'UT2004VR');
				Fire(0);
			}
		}
		bOldFire = bBtnFire;
		// waiting to join: UT's "Press FIRE to start!" is in the HUD layer now; you press fire, as in the original
	}
	if ( VRActive() )
	{
		UpdateEyeTextures();
		if ( bSeatedLevel && !bNeedHeight && AutoLevelSeconds > 0 )
		{
			SlowHeadZ += (RawHeadZ - SlowHeadZ) * FMin(1.0, DeltaTime / AutoLevelSeconds);
			HeightOffset = GameEyeMeters() - SlowHeadZ;
		}
	}
	if ( TestExec != "" && !bTestExecDone && Level.TimeSeconds > 3 && ((Pawn != None && (Pawn.Weapon != None || Vehicle(Pawn) != None)) || IsVRSpectating()) )
	{
		bTestExecDone = true;
		// a step that started a new level: carry on with the rest there (class defaults outlive the level)
		if ( default.TestExecCarry == "-" )
			TestExecNext = "";
		else if ( default.TestExecCarry != "" )
			TestExecNext = default.TestExecCarry;
		else
			TestExecNext = TestExec;
		if ( TestExecNext != "" )
		{
			default.TestExecCarry = "";
			RunTestExecStep();
		}
		if ( Pawn != None )
			Log("UT2004VR: TestExec '"$TestExec$"' on "$Pawn.Weapon.Class.Name$" -> grip "$GripOffsetFor(Pawn.Weapon), 'UT2004VR');
		else
			Log("UT2004VR: TestExec '"$TestExec$"' spectating", 'UT2004VR');
	}
	TickTestExec();
	Super.PlayerTick(DeltaTime);
	if ( AltHoldUntil > 0 )
		bAltFire = 1;   // debug VRAltHold: the button stays down (input resets it every frame)
}

// the stock first-person eye height above the floor, in meters (xPawn: CollisionHeight 44 + BaseEyeHeight 38)
simulated function float GameEyeMeters()
{
	local class<Pawn> PC;
	PC = PawnClass;
	if ( PC == None )
		PC = class'VRPawn';
	return (PC.default.CollisionHeight + PC.default.BaseEyeHeight + EyeHeightBonus) / UUPerMeter;
}

// UT's menu pauses the game and PlayerTick stops; VRLink (bAlwaysTick) keeps calling this so head tracking
// and the eye images stay live while paused (the world itself is frozen) and no pose backlog builds up
// left stick direction -> UT dodge direction (the stick's bigger axis); centred stick: no dodge
function EDoubleClickDir StickDodgeDir()
{
	if ( Abs(StickMX) < 0.3 && Abs(StickMY) < 0.3 )
	{
		Log("UT2004VR: dodge ignored (stick centred)", 'UT2004VR');
		return DCLICK_None;
	}
	if ( Abs(StickMX) >= Abs(StickMY) )
	{
		if ( StickMX > 0 ) return DCLICK_Right;
		return DCLICK_Left;
	}
	if ( StickMY > 0 ) return DCLICK_Forward;
	return DCLICK_Back;
}

// buttons that also work while UT's menu has paused the game: left Y (menu / hold to recenter), left X (scoreboard)
function VRButtonsTick()
{
	local GUIController G;
	local bool bOpen;

	// (held against the proxy's packets, which report every button each frame)
	if ( TapBtnUntil > 0 && Level.TimeSeconds > TapBtnUntil )
	{
		SetTapBtn(false);
		TapBtnUntil = 0;
	}
	else if ( TapBtnUntil > 0 )
		SetTapBtn(true);
	G = GUIController(Player.GUIController);
	bOpen = G != None && G.bActive;
	if ( bBtnMenu && !bOldMenu )
	{
		MenuBtnDownTime = Level.TimeSeconds;
		bMenuBtnLong = false;
		bMenuBtnSkip = false;
		if ( bOpen )
		{
			// like Esc: close the top menu page
			G.CloseMenu(true);
			bMenuBtnSkip = true;
		}
	}
	else if ( bBtnMenu && !bMenuBtnLong && !bMenuBtnSkip && Level.TimeSeconds - MenuBtnDownTime > 0.8 )
	{
		bMenuBtnLong = true;
		VRRecenter();
	}
	else if ( !bBtnMenu && bOldMenu && !bMenuBtnLong && !bMenuBtnSkip && !bOpen )
		ShowMenu();
	bOldMenu = bBtnMenu;
	if ( bBtnScores && !bOldScores )
		VRScores();
	bOldScores = bBtnScores;
}

exec function VRScores()
{
	bShowVRScores = !bShowVRScores;
	Log("UT2004VR: scoreboard "$bShowVRScores, 'UT2004VR');
}

function RunTestExecStep()
{
	local int i;
	local string Cmd;
	i = InStr(TestExecNext, "|");
	if ( i < 0 ) { Cmd = TestExecNext; TestExecNext = ""; }
	else { Cmd = Left(TestExecNext, i); TestExecNext = Mid(TestExecNext, i + 1); }
	TestExecFrames = 90;
	default.TestExecCarry = TestExecNext;
	if ( TestExecNext == "" )
		default.TestExecCarry = "-";   // sequence finished: don't restart it in a new level
	Log("UT2004VR: TestExec step '"$Cmd$"'", 'UT2004VR');
	ConsoleCommand(Cmd);
}

function TickTestExec()
{
	if ( TestExecNext != "" && --TestExecFrames <= 0 )
		RunTestExecStep();
}

// debug: run a command through the console's DelayedConsoleCommand, as UT's menus do (e.g. "start CTF-Face3?Game=...")
// debug: the spectator's "view next player" (what Fire does in state Spectating), with what's in the way
exec function VRSpecNext()
{
	local Controller C;
	for ( C = Level.ControllerList; C != None; C = C.NextController )
		Log("UT2004VR: spec candidate "$C$" canspectate "$Level.Game.CanSpectate(self, PlayerReplicationInfo.bOnlySpectator, C), 'UT2004VR');
	Log("UT2004VR: spec next: frozen "$bFrozen$" timer "$TimerRate$" state "$GetStateName()$" viewtarget "$ViewTarget, 'UT2004VR');
	ServerViewNextPlayer();
	Log("UT2004VR: spec next -> viewtarget "$ViewTarget$" behind "$bBehindView, 'UT2004VR');
}

exec function VRStateLog()
{
	Log("UT2004VR: state "$GetStateName()$" pawn "$Pawn$" cinematic "$IsCinematic()$" interp "$bInterpolating$" matinee "$bViewingMatineeCinematic$" game "$Level.Game.Class$" waiting "$Level.Game.bWaitingToStartMatch$" viewtarget "$ViewTarget$" vractive "$VRActive()$" packets "$Link.Packets$" bound "$Link.bBound$" last "$LastPacketTime$" now "$Level.TimeSeconds$" pauser "$Level.Pauser$" gui "$Player.GUIController.bActive$" eyes "$EyeTex[0]$" mirror "$MirrorIA, 'UT2004VR');
}

// debug: get into the nearest vehicle (as pressing use next to it would)
// debug: spawn a vehicle 900 uu ahead (the summon cheat drops it onto the player), e.g. VRSpawnVehicle Onslaught.ONSHoverTank
exec function VRSpawnVehicle(string ClassName, optional float Dist)
{
	local class<Vehicle> C;
	local Vehicle V;
	local rotator R;
	if ( Pawn == None || Level.NetMode != NM_Standalone )
		return;
	C = class<Vehicle>(DynamicLoadObject(ClassName, class'Class'));
	R.Yaw = Pawn.Rotation.Yaw;
	if ( C != None )
		V = Spawn(C,,, Pawn.Location + FMax(Dist, 900 * int(Dist == 0)) * vector(R) + vect(0,0,150), R);
	if ( V == None && C != None )
		V = Spawn(C,,, Pawn.Location + 200 * vector(R) + vect(0,0,40), R);
	if ( V == None && C != None )
		V = Spawn(C,,, Pawn.Location + 600 * vector(R) + vect(0,0,400), R);
	Log("UT2004VR: spawned "$V$" ("$C$")", 'UT2004VR');
}

// debug: the desktop window shows what is captured for the headset's overlay (the game type's HUD...)
exec function VRShowCapture()
{
	if ( VRHUD(myHUD) != None )
		VRHUD(myHUD).bDebugShowCapture = !VRHUD(myHUD).bDebugShowCapture;
}

// debug (VRBeamLog): the Link beam's start against the muzzle of the gun the eyes draw, measured at render time
function MeasureBeamGap()
{
	local int i;
	local LinkFire F;
	if ( Pawn == None || LinkGun(Pawn.Weapon) == None )
		return;
	for ( i = 0; i < 2; i++ )
	{
		F = LinkFire(Pawn.Weapon.GetFireMode(i));
		if ( F != None && F.Beam != None )
			BeamGap = VSize(F.Beam.Location - GunTarget);
	}
}

// debug: the neck model (VRNeck 1 forces it on) and the eye position against the gun's anchor
exec function VRNeck(optional int bOn)
{
	if ( bOn != 0 )
		NeckModelMode = 1;
	Log("UT2004VR: neck "$bNeckModel$" head yaw "$rotator(HeadF).Yaw$" eyes "$HeadPos$" body "$BodyHeadPos$" gun anchor world "$VRBodyWorld$" eyes world "$VRHeadWorld, 'UT2004VR');
}

// debug: strafe and log the gun lag every frame for 0.6 s
exec function VRLagTrace()
{
	VRStick("-1 0");
	LagTraceUntil = Level.TimeSeconds + 0.6;
}

// debug: the gun's rubber-band lag and the Link beam's start against the muzzle
exec function VRBeamLog()
{
	local int i;
	local LinkFire F;
	local float D;
	D = -1;
	if ( Pawn != None && LinkGun(Pawn.Weapon) != None )
		for ( i = 0; i < 2; i++ )
		{
			F = LinkFire(Pawn.Weapon.GetFireMode(i));
			if ( F != None && F.Beam != None )
				D = BeamGap;
		}
	Log("UT2004VR: beam log lag "$VSize(GunLag)$" uu, beam start to muzzle "$D$" uu, speed "$VSize(Pawn.Velocity), 'UT2004VR');
}

// debug: the HUD settings on this HUD and on the game type's one beside it
exec function VRHudLog()
{
	local VRHUD H;
	H = VRHUD(myHUD);
	if ( H == None )
		return;
	Log("UT2004VR: hud scale "$H.HudScale$" weaponbar "$H.bShowWeaponBar$" opacity "$H.HudOpacity$" crosshair "$H.CrosshairStyle
		$" | shadow "$H.Shadow$" scale "$H.Shadow.HudScale$" weaponbar "$H.Shadow.bShowWeaponBar$" opacity "$H.Shadow.HudOpacity, 'UT2004VR');
}

// debug: the vehicle's aim against the gaze
exec function VRAimLog()
{
	Log("UT2004VR: aim log pawn "$Pawn$" rot "$Pawn.Rotation$" head "$VRHeadRot$" state "$GetStateName(), 'UT2004VR');
}

exec function VREnterVehicle(optional string Part)
{
	local Vehicle V, Best;
	local float D, BestD;
	if ( Pawn == None || Vehicle(Pawn) != None )
		return;
	BestD = 1000000;
	foreach DynamicActors(class'Vehicle', V)
	{
		D = VSize(V.Location - Pawn.Location);
		if ( D < BestD && V.Driver == None && (ONSWeaponPawn(V) == None || Part != "") && (Part == "" || InStr(Caps(string(V.Class.Name)), Caps(Part)) >= 0) )
		{
			Best = V;
			BestD = D;
		}
	}
	if ( Best != None )
	{
		Log("UT2004VR: entering "$Best.Class.Name$" "$int(BestD)$" uu away", 'UT2004VR');
		Best.KDriverEnter(Pawn);
	}
}

// debug: set the (mouse) aim pitch, degrees
exec function VRAimPitch(float Deg)
{
	local rotator R;
	R = Rotation;
	R.Pitch = int(Deg * 65536.0 / 360.0) & 65535;
	SetRotation(R);
	LastLoggedPitch = R.Pitch;
	PitchLogUntil = Level.TimeSeconds + 6;
}

// debug: turn the (mouse) aim by Deg degrees at once, as a fast mouse flick
exec function VRAimYaw(float Deg)
{
	local rotator R;
	R = Rotation;
	R.Yaw += int(Deg * 65536.0 / 360.0);
	SetRotation(R);
	Log("UT2004VR: aim yaw flick "$Deg$" -> "$(R.Yaw & 65535), 'UT2004VR');
}

// debug: tilt the vehicle (15 deg pitch, 10 deg roll) and turn the aim (10 up, 20 left), as driving would
exec function VRTestTilt()
{
	local rotator R;
	if ( Vehicle(Pawn) == None )
		return;
	R = Pawn.Rotation;
	R.Pitch = 2730;
	R.Roll = 1820;
	Pawn.SetRotation(R);
	R = Rotation;
	R.Pitch = 1820;
	R.Yaw += -3640;
	SetRotation(R);
	Log("UT2004VR: tilted vehicle "$Pawn.Rotation$" aim "$Rotation, 'UT2004VR');
}

// debug: face the nearest vehicle of a class (name part), e.g. VRFaceVehicle AttackCraft
exec function VRGoNearVehicle(string Part)
{
	bVRGoNear = true;
	VRFaceVehicle(Part);
}

exec function VRFaceVehicle(string Part)
{
	local Vehicle V, Best;
	local float D, BestD;
	local rotator R;
	if ( Pawn == None )
		return;
	BestD = 1000000;
	foreach DynamicActors(class'Vehicle', V)
		if ( InStr(Caps(string(V.Class.Name)), Caps(Part)) >= 0 )
		{
			D = VSize(V.Location - Pawn.Location);
			if ( D < BestD ) { Best = V; BestD = D; }
		}
	if ( Best == None )
		return;
	if ( bVRGoNear )
	{
		// stand 400 uu in front of it (along its own forward), a little above
		Pawn.SetLocation(Best.Location + vector(Best.Rotation) * 400 + vect(0,0,60));
		bVRGoNear = false;
	}
	R = rotator(Best.Location - Pawn.Location);
	R.Pitch = 0;
	SetRotation(R);
	Log("UT2004VR: facing "$Best.Class.Name$" "$int(BestD)$" uu away, hidden "$Best.bHidden$" drawtype "$GetEnum(enum'EDrawType', Best.DrawType)$" mesh "$Best.Mesh$Best.StaticMesh$" ownernosee "$Best.bOwnerNoSee$" cull "$Best.CullDistance, 'UT2004VR');
}

function int SeatIndex(Vehicle V)
{
	local int i;
	if ( V == None )
		return -1;
	for ( i = 0; i < VehSeats.Length; i++ )
		if ( VehSeats[i].Vehicle ~= string(V.Class.Name) )
			return i;
	return -1;
}

function vector SeatOffsetFor(Vehicle V)
{
	local int i;
	i = SeatIndex(V);
	if ( i < 0 )
		return BuiltInSeat(V);
	return VehSeats[i].Offset;
}

// seats for vehicles you haven't set (VRSeat makes your own): ones whose UT camera sits inside the hull, where its
// faces point away from you and it can't be seen
function vector BuiltInSeat(Vehicle V)
{
	if ( V.IsA('ONSDualAttackCraft') )   // Cicada: camera at its centre, in the belly
		return vect(80,0,40);
	return vect(0,0,0);
}

function bool SeatShowsMesh(Vehicle V)
{
	local int i;
	i = SeatIndex(V);
	return i >= 0 && VehSeats[i].bShowMesh;
}

// hidden: the vehicle and its guns aren't drawn in your view (the Goliath's hull and turret fill it); others still see it
function bool SeatHidesMesh(Vehicle V)
{
	local int i;
	i = SeatIndex(V);
	return i >= 0 && VehSeats[i].bHideMesh;
}

function ShowVehicleMesh(Vehicle V, bool bShow)
{
	local int i;
	V.bOwnerNoSee = !bShow;
	if ( ONSVehicle(V) != None )
		for ( i = 0; i < ONSVehicle(V).Weapons.Length; i++ )
			if ( ONSVehicle(V).Weapons[i] != None )
				ONSVehicle(V).Weapons[i].bOwnerNoSee = !bShow;
}

function int SeatForEdit()
{
	local int i;
	i = SeatIndex(Vehicle(Pawn));
	if ( i < 0 && Vehicle(Pawn) != None )
	{
		i = VehSeats.Length;
		VehSeats.Length = i + 1;
		VehSeats[i].Vehicle = string(Pawn.Class.Name);
	}
	return i;
}

// console, in a vehicle: VRSeat <forward> <right> <up> moves your eyes in it (vehicle axes, uu ~ 2 cm), saved
exec function VRSeat(string S)
{
	local int i;
	i = SeatForEdit();
	if ( i < 0 )
		return;
	VehSeats[i].Offset = ParseVec(S);
	SaveTuning();
	VRSeatInfo();
}

// console, in a vehicle: show / hide the vehicle around you (whichever it isn't now), saved
exec function VRSeatMesh()
{
	local int i;
	i = SeatForEdit();
	if ( i < 0 )
		return;
	VehSeats[i].bShowMesh = Pawn.bOwnerNoSee;
	VehSeats[i].bHideMesh = !Pawn.bOwnerNoSee;
	ShowVehicleMesh(Vehicle(Pawn), VehSeats[i].bShowMesh);
	SaveTuning();
	VRSeatInfo();
}

exec function VRSeatInfo()
{
	local int i;
	i = SeatIndex(Vehicle(Pawn));
	if ( Vehicle(Pawn) == None )
		return;
	if ( i < 0 )
		ClientMessage("UT2004VR seat for "$Pawn.Class.Name$": default");
	else
		ClientMessage("UT2004VR seat for "$Pawn.Class.Name$": forward "$VehSeats[i].Offset.X$", right "$VehSeats[i].Offset.Y$", up "$VehSeats[i].Offset.Z$", vehicle "$VehSeats[i].bShowMesh$" shown / "$VehSeats[i].bHideMesh$" hidden");
}

exec function VRConsoleCmd(string Cmd)
{
	if ( Player != None && Player.Console != None )
		Player.Console.DelayedConsoleCommand(Cmd);
}

// debug: click UT's menu at window uv (0..1), as the trigger does
exec function VRMenuClick(string UV)
{
	local array<string> P;
	if ( Split(UV, " ", P) >= 2 )
		Menu.Click(GUIController(Player.GUIController), float(P[0]), float(P[1]));
}

// debug: log every clickable control of the open menu with its centre in window uv
exec function VRMenuDump()
{
	class'VRMenu'.static.Dump(GUIController(Player.GUIController));
}

function PausedVRTick()
{
	TickTestExec();
	if ( Link != None )
		Link.Drain();
	UpdateMenuState();
	VRButtonsTick();
	if ( VRActive() )
	{
		UpdateHeadWorld();
		UpdateEyeTextures();
	}
}

// the menu panel (VRMenu): state to the proxy, pointer, trigger clicks
function UpdateMenuState()
{
	if ( Menu == None )
		Menu = new class'VRMenu';
	// "M 0" once the eyes render: the proxy then leaves its own view (menus, loading) for them at once
	if ( VRActive() && EyeTex[0] != None && EyeTex[1] != None && MirrorIA != None )
		Menu.Update(Link, GUIController(Player.GUIController), bKeyboardMouse, bBtnFire, Level.TimeSeconds, 0);
	else
		Menu.Update(Link, GUIController(Player.GUIController), bKeyboardMouse, bBtnFire, Level.TimeSeconds, -1);
	bMenuOpen = Menu.bOpen;
}

simulated function bool VRActive()
{
	return Level.TimeSeconds - LastPacketTime < 1.0 && LastPacketTime > 0;
}

// ---------------------------------------------------------------------------
// Packets
// ---------------------------------------------------------------------------
static function vector V3(array<string> P, int i)
{
	local vector V;
	V.X = float(P[i]);
	V.Y = float(P[i+1]);
	V.Z = float(P[i+2]);
	return V;
}

function VRPacket(string Text)
{
	local array<string> P;
	local int n, e;
	local string Src;

	n = Split(Text, " ", P);
	if ( n < 1 )
		return;
	switch ( P[0] )
	{
	case "H":
		if ( n < 11 ) return;
		HeadSeq = int(P[1]);
		HeadPos = V3(P, 2);
		// calibrate once the headset is worn (field 11; older proxies: assume worn). If the room setup
		// is missing or odd (WMR "Cannot locate root anchor": the floor is unknown, heads read < 0 m), or the
		// player is seated, lift the head to StandEyeMeters; plausible standing heights stay real.
		// a worn headset always moves a little; one lying on the desk is perfectly still (the WMR driver reports
		// "worn" late, and calibrating from the desk gave 0.94 m and the desk's direction as the chair forward)
		if ( Level.TimeSeconds - MotionRefTime > 0.5 )
		{
			if ( VSize(HeadPos - MotionRefPos) > 0.003 || (Normal(HeadF) dot Normal(MotionRefF)) < 0.99995 )
				LastHeadMotion = Level.TimeSeconds;
			MotionRefPos = HeadPos;
			MotionRefF = HeadF;
			MotionRefTime = Level.TimeSeconds;
		}
		if ( ((n > 11 && P[11] == "1") || n <= 11) && Level.TimeSeconds - LastHeadMotion < 1.5 )
			WornTime += Level.TimeSeconds - LastPacketTimeH;
		else
			WornTime = 0;
		LastPacketTimeH = Level.TimeSeconds;
		RawHeadZ = HeadPos.Z;
		// average the head height over ~1.5 s of wearing before calibrating (not one instant)
		if ( bNeedHeight && bAutoHeight && WornTime > 0.5 )
		{
			CalibSum += HeadPos.Z;
			CalibCount++;
		}
		// the chair's forward (and natural head pitch): the average gaze over ~1.3 s of looking roughly level (within
		// ~10 deg of the horizon). Glances down at the keyboard don't count: taken while looking down and aside, it
		// left the keyboard/mouse gun off the view centre for the whole game. Only once (and again on recenter).
		// worn = the head moved in the last 20 s (not the height's stricter "moving right now": sitting still at the
		// keyboard, that took over a minute, with a fallback chair from a downward glance). Not the worn flag: WMR
		// reports worn on the desk too, and the chair then got the desk's direction (the gun off to one side once
		// the headset went on).
		if ( !bChairMeasured && LastHeadMotion > 0 && Level.TimeSeconds - LastHeadMotion < 20
			&& Abs(Normal(HeadF).Z) < 0.17 )
		{
			CalibFwdSum += Normal(HeadF);
			if ( ++ChairCount >= 120 )
			{
				// your level gaze while wearing and moving the headset: where you face as you play (SteamVR's seated
				// calibration was used here, but it can be ~30 deg off how you sit today, and the gun swung there)
				ChairYaw = rotator(CalibFwdSum).Yaw;
				Src = "level gaze";
				if ( bSeatZero )
					Src = "level gaze; seated calibration " $ rotator(SeatZeroF).Yaw;
				bChairFromGaze = false;
				ChairPitch = rotator(CalibFwdSum).Pitch;
				bChairYawValid = true;
				bChairMeasured = true;
				CalibFwdSum = vect(0,0,0);
				ChairCount = 0;
				Log("UT2004VR: chair forward yaw "$ChairYaw$" ("$Src$") pitch "$ChairPitch$" (level gaze)", 'UT2004VR');
			}
		}
		if ( bNeedHeight && bAutoHeight && WornTime > 2.0 && CalibCount > 0 )
		{
			HeadPos.Z = CalibSum / CalibCount;
			bNeedHeight = false;
			if ( bMatchGameHeight )
				HeightOffset = GameEyeMeters() - HeadPos.Z;
			else if ( bForceHeight || HeadPos.Z < 1.4 || HeadPos.Z > 2.3 )
				HeightOffset = StandEyeMeters - HeadPos.Z;
			else
				HeightOffset = 0;
			bForceHeight = false;
			bSeatedLevel = bSeatedAutoLevel && bMatchGameHeight && HeadPos.Z < 1.4;
			SlowHeadZ = HeadPos.Z;
			Log("UT2004VR: height calibrated, head "$HeadPos.Z$" m (avg of "$CalibCount$") -> offset "$HeightOffset$" seated auto-level="$bSeatedLevel, 'UT2004VR');
			CalibSum = 0;
			CalibCount = 0;
			HeadPos.Z = RawHeadZ;
		}
		HeadPos.Z += HeightOffset;
		HeadF = V3(P, 5);
		HeadU = V3(P, 8);
		if ( n > 12 )
			NeckModel(int(P[12]));
		else
			NeckModel(200);
		LastPacketTime = Level.TimeSeconds;
		break;
	case "L":
	case "R":
		if ( n < 11 ) return;
		e = 0;
		if ( P[0] == "R" ) e = 1;
		bHandOK[e] = byte(P[1] == "1");
		HandPos[e] = V3(P, 2);
		HandPos[e].Z += HeightOffset;
		HandF[e] = V3(P, 5);
		HandU[e] = V3(P, 8);
		break;
	case "I":
		if ( n < 8 ) return;
		StickMX = float(P[1]);
		StickMY = float(P[2]);
		StickTX = float(P[3]);
		StickTY = float(P[4]);
		bBtnJump = P[5] == "1";
		bBtnCrouch = P[6] == "1";
		bBtnMenu = P[7] == "1";
		if ( n >= 12 )
		{
			bBtnFire = P[8] == "1";
			bBtnAlt = P[9] == "1";
			bBtnNext = P[10] == "1";
			bBtnPrev = P[11] == "1";
		}
		if ( n >= 14 )
		{
			bBtnDodge = P[12] == "1";
			bBtnScores = P[13] == "1";
		}
		if ( n >= 15 )
			bBtnUse = P[14] == "1";
		break;
	case "Z":
		// SteamVR's seated calibration (as SteamVR Home uses it)
		if ( n >= 11 )
		{
			SeatZeroPos = V3(P, 2);
			SeatZeroF = V3(P, 5);
			bSeatZero = VSize(SeatZeroF) > 0.5;
		}
		break;
	case "E":
		if ( n < 11 ) return;
		e = Clamp(int(P[1]), 0, 1);
		EyeOfs[e] = V3(P, 2);
		EyeF[e] = V3(P, 5);
		EyeU[e] = V3(P, 8);
		break;
	case "U":
		// the controller's pointer on the menu panel (0..1): move UT's menu cursor there
		if ( n < 3 || Menu == None ) return;
		Menu.Pointer(GUIController(Player.GUIController), float(P[1]), float(P[2]), bKeyboardMouse);
		break;
	case "K":
		if ( n < 4 ) return;
		MirrorEye = int(P[1]);
		MirrorHX = float(P[2]);
		MirrorVY = float(P[3]);
		break;
	case "C":
		if ( n < 4 ) return;
		EyeFOV = int(P[1]);
		EyeW = int(P[2]);
		EyeH = int(P[3]);
		break;
	}
}

// ---------------------------------------------------------------------------
// Transforms
// ---------------------------------------------------------------------------
simulated function rotator PlayRot()
{
	local rotator R;
	R.Yaw = PlayYaw;
	return R;
}

simulated function rotator FrameRot(vector F, vector U)
{
	F = Normal(F);
	U = Normal(U);
	return OrthoRotation(F, Normal(U cross F), U);
}

// playspace (meters) -> world offset (uu)
simulated function vector PlayToWorld(vector V)
{
	return (V * UUPerMeter) >> PlayRot();
}

simulated function float FloorZ()
{
	if ( Pawn != None )
		return Pawn.Location.Z - Pawn.CollisionHeight;
	return Location.Z;
}

simulated function vector BaseXY()
{
	local vector B;
	if ( Pawn != None )
		B = Pawn.Location;
	else
		B = Location;
	B.Z = FloorZ();
	return B;
}

// head position in the world: the pawn's floor point + the head's offset from the anchor
// rotate V about the unit axis A by Ang radians (Rodrigues)
static function vector RotAbout(vector V, vector A, float Ang)
{
	return V * Cos(Ang) + (A cross V) * Sin(Ang) + A * ((A dot V) * (1 - Cos(Ang)));
}

// playspace direction -> world direction (yaw only: the VR playspace, or the mouse heading in keyboard/mouse mode)
simulated function vector PlayDir(vector V)
{
	local rotator ChairR, YawR;
	if ( bKeyboardMouse && bChairYawValid )
	{
		ChairR.Yaw = ChairYaw;
		YawR.Yaw = Rotation.Yaw;
		return (V << ChairR) >> YawR;
	}
	return V >> PlayRot();
}

// keyboard/mouse: the mouse pitch tilts the view about the head's own right axis, so it can only tilt
// up/down, never roll the view (pitching about the body's axis rolled it whenever the head was turned)
simulated function MousePitchView(out vector F, out vector U)
{
	local vector Ax;
	local float Ang;
	local rotator R;
	local int P;

	// while the menu panel floats in the room, no extra mouse tilt: it would rotate the world relative to the
	// room-fixed panel in a way that changes as you turn your head (looks like the panel rolling)
	if ( !bKeyboardMouse || !bChairYawValid || bMenuOpen )
		return;
	R = CleanAim(Rotation);
	// the mouse pitch, minus your natural head pitch (so a level aim is centred while you hold your head as usual)
	P = (R.Pitch - ChairPitch) & 65535;
	if ( P > 32768 )
		P -= 65536;
	if ( P == 0 )
		return;
	Ang = float(P) * 3.14159265 / 32768.0;
	Ax = Normal(U cross F);        // the head's right axis
	// UT pitch > 0 looks up: rotate forward toward up, i.e. about -right
	F = Normal(RotAbout(F, -Ax, Ang));
	U = Normal(RotAbout(U, -Ax, Ang));
}

// the game type's HUD layer (VRHUD kind 3): a flat 16:9 picture in front of the head, metres at HudDistance
simulated function float LayerHalfRight()
{
	return 0.62 * HudSpread * OriginalHudScale;
}

simulated function float LayerHalfUp()
{
	if ( WinW <= 0 )
		return LayerHalfRight() * 9 / 16;
	return LayerHalfRight() * WinH / WinW;
}

simulated function float LayerCentreUp()
{
	return ((HudTopUp + HudBottomUp) * 0.5 - HudLower) * HudSpread;
}

// the layer's width in this eye's pixels (for the HUD's ResScale and fonts)
simulated function float LayerPixels(ScriptedTexture Tex)
{
	return Tex.USize * (LayerHalfRight() / HudDistance) / Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
}

// a point on the layer (metres from its centre, right / up) -> pixel in this eye
simulated function bool LayerPoint(ScriptedTexture Tex, vector Loc, rotator Rot, float R, float U, out float PX, out float PY)
{
	local vector X, Y, Z;
	GetAxes(VRHeadRot, X, Y, Z);
	return HudProject(Tex, VRHeadWorld + (X * HudDistance + Y * R + Z * (LayerCentreUp() + U)) * UUPerMeter, Loc, Rot, PX, PY);
}

simulated function bool UsingOriginalHud()
{
	return bVROriginalHud && VRHUD(myHUD) != None && VRHUD(myHUD).Shadow != None;
}

// spectating (a spectator, or a player watching before joining): UT shows its spectator bar then
simulated function bool IsVRSpectating()
{
	return Pawn == None && !IsInState('Dead') && !IsCinematic()
		&& (IsInState('Spectating') || (PlayerReplicationInfo != None && PlayerReplicationInfo.bOnlySpectator));
}

// a Matinee cinematic carries the controller itself (UT's intro, NvidiaLogo.ut2 in CinematicGame): no pawn
simulated function bool IsCinematic()
{
	return Pawn == None && (bInterpolating || bViewingMatineeCinematic || CinematicGame(Level.Game) != None);
}

// no pawn and not dead: a cinematic, waiting for the match ("press fire to start"), spectating. The eyes go to UT's
// own camera with the head tracked on top, so you can always look around.
simulated // the free view's heading (see the intro anchor in the view code): upgrades from the startup headset pose to the
// seated calibration, to your head once you wear it, to your chair's forward once measured. Your head's heading is
// taken once and only replaced by the chair when they are 20 deg apart (no small jump mid-intro).
function CineYawFrom()
{
	local int d;

	if ( CineYawSrc < 3 && bChairMeasured )
	{
		d = ((ChairYaw - CineRefYaw + 32768) & 65535) - 32768;
		if ( CineYawSrc < 2 || Abs(d) > 3640 )
		{
			CineRefYaw = ChairYaw;
			Log("UT2004VR: free view faces your chair, yaw "$ChairYaw$" ("$(d * 360 / 65536)$" deg turn)", 'UT2004VR');
		}
		CineYawSrc = 3;
	}
	else if ( CineYawSrc < 2 && WornTime > 0.5 )
	{
		CineRefYaw = rotator(HeadF).Yaw;
		CineYawSrc = 2;
		Log("UT2004VR: free view faces your head, yaw "$CineRefYaw, 'UT2004VR');
	}
	else if ( CineYawSrc < 1 && bSeatZero )
	{
		CineRefYaw = rotator(SeatZeroF).Yaw;
		CineYawSrc = 1;
	}
}

function bool IsFreeView()
{
	return Pawn == None && !IsInState('Dead');
}

simulated function UpdateHeadWorld()
{
	local vector Ofs, F, U;
	local rotator RefR, CamR;

	if ( IsFreeView() )
	{
		// eyes at the cinematic (or waiting/spectating) camera; your head's moves since the intro started are added, turned with the
		// camera's heading (yaw only: the horizon stays level whatever the camera pitches or rolls)
		// the anchor waits for real head data (before the first packet HeadPos is zero, which would add your whole
		// head height on top of the camera)
		// facing where you sit: your chair's forward once it is measured (your level gaze), before that your head's
		// heading once you wear the headset. SteamVR's seated calibration only while the headset isn't on: at
		// startup it often lies on the desk, facing anywhere, and the calibration can be far off how you sit
		// today (107 deg once: the intro played behind you to the left). The position is your head's, taken again
		// once you wear it (the calibration's can be half a metre off and well below your head).
		if ( !bCineAnchored && VRActive() && VSize(HeadPos) > 0.1 )
		{
			if ( CineWaitStart == 0 )
				CineWaitStart = Level.TimeSeconds;
			CineAnchor = HeadPos;   // meanwhile the eyes stay at the camera
			// the calibration comes with the proxy's static packets (~every 0.7 s): wait for it a moment
			if ( bChairMeasured || WornTime > 0.5 || bSeatZero || Level.TimeSeconds - CineWaitStart > 1.5 )
			{
				bCineAnchored = true;
				bCinePosWorn = WornTime > 0.5;
				CineAnchor = HeadPos;
				CineYawSrc = 0;
				CineRefYaw = rotator(HeadF).Yaw;
				CineYawFrom();
				Log("UT2004VR: free view anchored, yaw "$CineRefYaw$" (source "$CineYawSrc$": 0 headset, 1 seated, 2 head, 3 chair) head "$HeadPos$" worn "$bCinePosWorn, 'UT2004VR');
			}
		}
		if ( bCineAnchored && !bCinePosWorn && WornTime > 0.5 )
		{
			bCinePosWorn = true;
			CineAnchor = HeadPos;
			Log("UT2004VR: free view: headset on, anchored at your head "$HeadPos, 'UT2004VR');
		}
		if ( bCineAnchored )
			CineYawFrom();
		RefR.Yaw = CineRefYaw;
		if ( bCineCam )
		{
			CamR.Yaw = CineCamRot.Yaw;
			VRHeadWorld = CineCamLoc + ((((HeadPos - CineAnchor) * UUPerMeter) << RefR) >> CamR);   // (vector >> binds looser than +)
		}
		else
		{
			CamR.Yaw = Rotation.Yaw;
			VRHeadWorld = Location + ((((HeadPos - CineAnchor) * UUPerMeter) << RefR) >> CamR);   // (vector >> binds looser than +)
		}
		F = (HeadF << RefR) >> CamR;
		U = (HeadU << RefR) >> CamR;
		VRHeadRot = FrameRot(F, U);
		return;
	}

	// riding a guided Redeemer (alt-fire): the eyes at the warhead, turned with its flight (yaw and pitch, as in 2D;
	// its banking only with bRedeemerRoll), your head's moves since launch added on top
	if ( IsRiding() )
	{
		if ( Pawn != LastWarhead )
		{
			LastWarhead = Pawn;
			WarAnchor = HeadPos;
			if ( bChairYawValid )
				WarRefYaw = ChairYaw;
			else
				WarRefYaw = rotator(HeadF).Yaw;
			Log("UT2004VR: riding "$Pawn.Class.Name, 'UT2004VR');
		}
		RefR.Yaw = WarRefYaw;
		CamR = Pawn.Rotation;
		if ( !bRedeemerRoll )
			CamR.Roll = 0;
		VRHeadWorld = Pawn.Location + ((((HeadPos - WarAnchor) * UUPerMeter) << RefR) >> CamR);
		F = (HeadF << RefR) >> CamR;
		U = (HeadU << RefR) >> CamR;
		VRHeadRot = FrameRot(F, U);
		if ( bDebugLog && Level.TimeSeconds > NextScopeLog )
		{
			NextScopeLog = Level.TimeSeconds + 0.5;
			Log("UT2004VR: riding at "$Pawn.Location$" flight "$Pawn.Rotation$" eyes "$VRHeadRot$" yaw accel "$RedeemerWarhead(Pawn).YawAccel$" pitch accel "$RedeemerWarhead(Pawn).PitchAccel, 'UT2004VR');
		}
		return;
	}
	LastWarhead = None;

	// in a vehicle (or a turret): the eyes at its driver camera (FPCamPos), your head's moves since you got in
	// added, turned with the vehicle's heading (yaw only: the horizon stays level over bumps and slopes)
	if ( Vehicle(Pawn) != None )
	{
		if ( Pawn != LastVehicle )
		{
			LastVehicle = Vehicle(Pawn);
			TurretEntryYaw = Pawn.Rotation.Yaw;
			VehViewYaw = Pawn.Rotation.Yaw;
			LastViewYawT = Level.TimeSeconds;
			VehAnchor = HeadPos;
			if ( bChairYawValid )
				VehRefYaw = ChairYaw;
			else
				VehRefYaw = rotator(HeadF).Yaw;
			// first person: UT then hides the vehicle mesh where it wants to (bDrawMeshInFP) and the driver
			if ( bBehindView )
			{
				bBehindView = false;
				LastVehicle.POVChanged(self, true);
			}
			Log("UT2004VR: in vehicle "$LastVehicle.Class.Name$" camera "$LastVehicle.FPCamPos$" +view "$LastVehicle.FPCamViewOffset$" mesh in FP "$LastVehicle.bDrawMeshInFP$" collision "$LastVehicle.CollisionRadius$"/"$LastVehicle.CollisionHeight$" relative aim "$LastVehicle.bPCRelativeFPRotation, 'UT2004VR');
		}
		RefR.Yaw = VehRefYaw;
		CamR.Yaw = VehicleViewYaw();
		// UT's first-person camera: FPCamPos in the vehicle's frame, then FPCamViewOffset along the view (the
		// Goliath's camera is 90 uu ahead of its pivot); here along the vehicle's heading, so the eyes don't swing
		// on a long neck when you turn your head. Plus your own seat offset (VRSeat).
		if ( bBehindView )
			VRHeadWorld = VehicleChaseCam(LastVehicle, CamR.Yaw) + ((((HeadPos - VehAnchor) * UUPerMeter) << RefR) >> CamR);
		else
			VRHeadWorld = LastVehicle.GetCameraLocationStart() + ((LastVehicle.FPCamPos + SeatOffsetFor(LastVehicle)) >> VehicleFrame())
				+ (LastVehicle.FPCamViewOffset >> CamR)
				+ ((((HeadPos - VehAnchor) * UUPerMeter) << RefR) >> CamR);
		F = (HeadF << RefR) >> CamR;
		U = (HeadU << RefR) >> CamR;
		VRHeadRot = FrameRot(F, U);
		return;
	}
	LastVehicle = None;
	bCineAnchored = false;   // the next free view (cinematic, waiting) anchors the head afresh
	CineWaitStart = 0;
	Ofs = HeadPos - Anchor;
	Ofs.Z = HeadPos.Z;
	VRHeadWorld = BaseXY() + PlayToWorld(Ofs);
	Ofs = BodyHeadPos - Anchor;
	Ofs.Z = BodyHeadPos.Z;
	VRBodyWorld = BaseXY() + PlayToWorld(Ofs);
	F = PlayDir(HeadF);
	U = PlayDir(HeadU);
	MousePitchView(F, U);
	VRHeadRot = FrameRot(F, U);
	if ( IsBehindOnFoot() )
		VRHeadWorld = BehindCamera(VRHeadWorld);
}

// behind view (F) on foot: you see your character, from behind and above
simulated function bool IsBehindOnFoot()
{
	return bBehindView && Pawn != None && Vehicle(Pawn) == None && !IsRiding() && VRActive();
}

// back along your body's facing (the chair's forward, turned like the view): turning your head doesn't swing the
// camera around the character; stops short of walls
simulated function vector BehindCamera(vector Eyes)
{
	local rotator R;
	local vector Fwd, Right, Cam, HitL, HitN;
	if ( bChairYawValid )
		R.Yaw = ChairYaw;
	Fwd = PlayDir(vector(R));
	Fwd.Z = 0;
	Fwd = Normal(Fwd);
	Right = Normal(vect(0,0,1) cross Fwd);
	Cam = Eyes + (vect(0,0,1) * BehindHeight - Fwd * BehindDistance + Right * BehindRight) * UUPerMeter;
	if ( Trace(HitL, HitN, Cam, Eyes, false) != None )
		Cam = HitL + HitN * 8;
	return Cam;
}

simulated function GetEyeView(int Eye, out vector Loc, out rotator Rot)
{
	local vector F, U, HX, HY, HZ, O;

	// eye axes and offset expressed in the (pitched) head frame
	GetAxes(VRHeadRot, HX, HY, HZ);
	O = EyeOfs[Eye] * UUPerMeter;
	Loc = VRHeadWorld + O.X * HX + O.Y * HY + O.Z * HZ;
	F = EyeF[Eye].X * HX + EyeF[Eye].Y * HY + EyeF[Eye].Z * HZ;
	U = EyeU[Eye].X * HX + EyeU[Eye].Y * HY + EyeU[Eye].Z * HZ;
	Rot = FrameRot(F, U);
}

simulated function GetHandWorld(int H, out vector Loc, out vector Dir)
{
	local vector Ofs;
	Ofs = HandPos[H] - Anchor;
	Ofs.Z = HandPos[H].Z;
	Loc = BaseXY() + PlayToWorld(Ofs);
	Dir = Normal(HandF[H] >> PlayRot());
}

// ---------------------------------------------------------------------------
// Gun in the right hand
// ---------------------------------------------------------------------------
simulated function bool GunActive()
{
	// (not in a vehicle: Assault's turrets and fighters carry a Weapon, but you don't hold it)
	return bWeapons && VRActive() && (bHandOK[1] != 0 || bKeyboardMouse) && Pawn != None && Vehicle(Pawn) == None;
}

simulated function rotator GunRot()
{
	local rotator R;
	local vector X, Y, Z, X2, Z2;
	local float A;

	R = FrameRot(HandF[1] >> PlayRot(), HandU[1] >> PlayRot());
	if ( GunPitchOffset == 0 )
		return R;
	// pitch about the controller's own right axis (positive = barrel up)
	GetAxes(R, X, Y, Z);
	A = GunPitchOffset * 3.14159265 / 32768.0;
	X2 = X * Cos(A) + Z * Sin(A);
	Z2 = Z * Cos(A) - X * Sin(A);
	return OrthoRotation(X2, Y, Z2);
}

// keyboard/mouse: a small rubber band - when the head moves (strafing, walking, jumping, crouching) the gun first stays
// behind, at most GunLagMax metres, and eases back over GunLagTime seconds; GunLagSmooth eases it in and out. Turning doesn't move the head: no lag.
simulated function vector KBMGunLag()
{
	local vector D;
	local float Dt;

	if ( GunLagTime <= 0 || GunLagMax <= 0 )
		return vect(0,0,0);
	if ( Level.TimeSeconds != GunLagAt )
	{
		Dt = Level.TimeSeconds - GunLagAt;
		D = VRHeadWorld - GunLagHead;
		GunLagAt = Level.TimeSeconds;
		GunLagHead = VRHeadWorld;
		// a respawn, teleport or level start: no lag
		if ( Dt <= 0 || Dt > 0.5 || VSize(D) > 2.0 * UUPerMeter )
		{
			GunLagRaw = vect(0,0,0);
			GunLag = vect(0,0,0);
		}
		else
		{
			GunLagRaw = GunLagRaw * Exp(-Dt / GunLagTime) - D;
			if ( VSize(GunLagRaw) > GunLagMax * UUPerMeter )
				GunLagRaw = Normal(GunLagRaw) * GunLagMax * UUPerMeter;
			// what you see eases toward it, so the gun starts drifting gently instead of jumping on the first step
			if ( GunLagSmooth > 0 )
				GunLag += (GunLagRaw - GunLag) * (1 - Exp(-Dt / GunLagSmooth));
			else
				GunLag = GunLagRaw;
		}
		if ( Level.TimeSeconds < LagTraceUntil )
			Log("UT2004VR: lag trace t "$(Level.TimeSeconds - (LagTraceUntil - 0.6))$" raw "$VSize(GunLagRaw)$" shown "$VSize(GunLag), 'UT2004VR');
	}
	return GunLag;
}

simulated function vector GunTip()
{
	local vector Loc, Dir, X, Y, Z;
	if ( bKeyboardMouse )
	{
		// keyboard/mouse: a fixed "hand" in front of the chest that turns and pitches with the mouse aim, as one
		// piece about the eyes: the chest drop is along the aim's own up, so tilting the view with the mouse keeps the
		// gun where it sits in view (with the drop along the world's up it pivoted about the chest and swung toward
		// or away from the face). Level aim: the same place as before. It follows the head's position (not the
		// pawn's), so where it sits in view doesn't depend on how you sat when the session started (before the
		// height calibration a floor-based chest point put it above the view, upside down); head turns stay freelook.
		// on the head without its turning arc: turning your head doesn't move the gun (moving and leaning do)
		Loc = VRBodyWorld + KBMGunLag();
		if ( VSize(BodyHeadPos) == 0 )
			Loc = VRHeadWorld + KBMGunLag();
		GetAxes(CleanAim(Rotation), X, Y, Z);
		return Loc + KBMGunOffset.X * X + KBMGunOffset.Y * Y + (KBMGunOffset.Z - KBMChestBelowEyes * UUPerMeter) * Z;
	}
	GetHandWorld(1, Loc, Dir);
	return Loc;
}

simulated function bool GetMuzzle(out vector Muzzle)
{
	if ( !GunActive() )
		return false;
	// the muzzle as last placed, moved on with the pawn since: weapons and the Link beam ask during their own Tick,
	// after the pawn moved this frame but before the gun is placed again for the eyes (the beam trailed the gun
	// by a frame of movement, ~10 uu while strafing)
	if ( bGunCalibrated )
		Muzzle = GunTarget + (Pawn.Location - GunTargetPawnLoc);
	else
		Muzzle = GunTip() + vector(Rotation) * MuzzleForward;
	return true;
}

function bool IsFlipped(class<Actor> C)
{
	local int i;
	for ( i = 0; i < FlipGuns.Length; i++ )
		if ( FlipGuns[i] ~= string(C) )
			return true;
	return false;
}

// the offset entry for a weapon: its own class first, else the nearest class it is made from (ClassicShockRifle and
// the InstaGib rifles use ShockRifle's, ClassicFlakCannon FlakCannon's...). -1: none. Cached per weapon class/mode.
function int FindGrip(array<VRTuning.GripOfs> L, Weapon W)
{
	local int i, Best;
	local class<Object> C, BestC;
	if ( W.Class == GripCacheClass && bKeyboardMouse == bGripCacheKBM )
		return GripCacheIdx;
	Best = -1;
	for ( i = 0; i < L.Length; i++ )
	{
		if ( L[i].Gun ~= string(W.Class.Name) )
		{
			Best = i;
			break;
		}
		C = GunClass(L[i].Gun, W);
		if ( C != None && ClassIsChildOf(W.Class, C) && (Best < 0 || ClassIsChildOf(C, BestC)) )
		{
			Best = i;
			BestC = C;
		}
	}
	GripCacheClass = W.Class;
	bGripCacheKBM = bKeyboardMouse;
	GripCacheIdx = Best;
	if ( Best >= 0 && !(L[Best].Gun ~= string(W.Class.Name)) )
		Log("UT2004VR: "$W.Class.Name$" uses the "$L[Best].Gun$" grip", 'UT2004VR');
	return Best;
}

// an entry's weapon class by its name (entries carry no package)
function class<Object> GunClass(string N, Weapon W)
{
	local class<Object> C;
	C = class<Object>(DynamicLoadObject(string(W.Class.Outer.Name)$"."$N, class'Class', true));
	if ( C == None ) C = class<Object>(DynamicLoadObject("XWeapons."$N, class'Class', true));
	if ( C == None ) C = class<Object>(DynamicLoadObject("Onslaught."$N, class'Class', true));
	if ( C == None ) C = class<Object>(DynamicLoadObject("UTClassic."$N, class'Class', true));
	if ( C == None ) C = class<Object>(DynamicLoadObject("OnslaughtFull."$N, class'Class', true));
	return C;
}

function vector GripOffsetFor(Weapon W)
{
	local int i;
	if ( W == None )
		return vect(0,0,0);
	// keyboard/mouse mode: its own offsets (the gun sits in front of the chest, not in a hand; the hand-tuned ones
	// put some guns, e.g. the Link Gun, in the middle of the view)
	if ( bKeyboardMouse )
	{
		i = FindGrip(KBMGrips, W);
		if ( i >= 0 )
			return KBMGrips[i].Offset;
		return vect(0,0,0);
	}
	i = FindGrip(Grips, W);
	if ( i >= 0 )
		return Grips[i].Offset;
	return vect(0,0,0);
}

// console: VRGrip <forward> <right> <up> - move the current gun in your hand (gun axes, uu ~ 2 cm), saved per weapon
// UT's console did not pass three float parameters reliably (only the first arrived), so the
// multi-value commands take the rest of the line and parse it here
static function vector ParseVec(string S)
{
	local array<string> P;
	local vector V;
	local int i, k;

	Split(S, " ", P);
	for ( i = 0; i < P.Length; i++ )
	{
		if ( P[i] == "" )
			continue;
		if ( k == 0 ) V.X = float(P[i]);
		else if ( k == 1 ) V.Y = float(P[i]);
		else if ( k == 2 ) V.Z = float(P[i]);
		k++;
	}
	return V;
}

exec function VRGrip(string S)
{
	local int i;
	local string N;
	local vector V;

	if ( Pawn == None || Pawn.Weapon == None )
		return;
	N = string(Pawn.Weapon.Class.Name);
	V = ParseVec(S);
	GripCacheClass = None;
	if ( bKeyboardMouse )
	{
		for ( i = 0; i < KBMGrips.Length; i++ )
			if ( KBMGrips[i].Gun ~= N )
				break;
		if ( i == KBMGrips.Length )
		{
			KBMGrips.Length = i + 1;
			KBMGrips[i].Gun = N;
		}
		KBMGrips[i].Offset = V;
	}
	else
	{
		for ( i = 0; i < Grips.Length; i++ )
			if ( Grips[i].Gun ~= N )
				break;
		if ( i == Grips.Length )
		{
			Grips.Length = i + 1;
			Grips[i].Gun = N;
		}
		Grips[i].Offset = V;
	}
	SaveTuning();
	VRGripInfo();
}

exec function VRGripReset()
{
	local int i;
	if ( Pawn == None || Pawn.Weapon == None )
		return;
	GripCacheClass = None;
	if ( bKeyboardMouse )
	{
		for ( i = 0; i < KBMGrips.Length; i++ )
			if ( KBMGrips[i].Gun ~= string(Pawn.Weapon.Class.Name) )
			{
				KBMGrips.Remove(i, 1);
				break;
			}
	}
	else
		for ( i = 0; i < Grips.Length; i++ )
			if ( Grips[i].Gun ~= string(Pawn.Weapon.Class.Name) )
			{
				Grips.Remove(i, 1);
				break;
			}
	SaveTuning();
	VRGripInfo();
}

exec function VRGripInfo()
{
	local vector O;
	local int i;
	local string From;
	if ( Pawn == None || Pawn.Weapon == None )
		return;
	O = GripOffsetFor(Pawn.Weapon);
	if ( bKeyboardMouse )
		i = FindGrip(KBMGrips, Pawn.Weapon);
	else
		i = FindGrip(Grips, Pawn.Weapon);
	if ( i < 0 )
		From = " (none set)";
	else if ( bKeyboardMouse && !(KBMGrips[i].Gun ~= string(Pawn.Weapon.Class.Name)) )
		From = " (from "$KBMGrips[i].Gun$")";
	else if ( !bKeyboardMouse && !(Grips[i].Gun ~= string(Pawn.Weapon.Class.Name)) )
		From = " (from "$Grips[i].Gun$")";
	if ( bKeyboardMouse )
		ClientMessage("UT2004VR keyboard-mode grip for "$Pawn.Weapon.Class.Name$": forward "$O.X$", right "$O.Y$", up "$O.Z$From);
	else
		ClientMessage("UT2004VR grip for "$Pawn.Weapon.Class.Name$": forward "$O.X$", right "$O.Y$", up "$O.Z$From);
	Log("UT2004VR: grip info "$Pawn.Weapon.Class.Name$" kbm "$bKeyboardMouse$" "$O$From, 'UT2004VR');
}

// console: VRGunFlip - turn the gun in your hand upside down (saved per weapon)
exec function VRGunFlip()
{
	local int i;
	local Actor A;

	if ( Pawn == None || Pawn.Weapon == None || Pawn.Weapon.ThirdPersonActor == None )
		return;
	A = Pawn.Weapon.ThirdPersonActor;
	for ( i = 0; i < FlipGuns.Length; i++ )
		if ( FlipGuns[i] ~= string(A.Class) )
			break;
	if ( i < FlipGuns.Length )
		FlipGuns.Remove(i, 1);
	else
		FlipGuns[FlipGuns.Length] = string(A.Class);
	i = FindCal(A.Class);
	if ( i >= 0 )
	{
		GunCals[i].Zb = -GunCals[i].Zb;
		GunCals[i].Yb = -GunCals[i].Yb;
	}
	SaveTuning();
}

function int FindCal(class<Actor> C)
{
	local int i;
	for ( i = 0; i < GunCals.Length; i++ )
		if ( GunCals[i].Cls == C )
			return i;
	return -1;
}

// Measure a third-person weapon model once, at rest. Barrel = the 'tip' bone's X axis (UT emits the
// muzzle flash along it), pointing out of the front of the gun; up = the mesh's own +Z (guns are
// modelled upright); grip = where the model normally hangs from the hand bone (its default
// RelativeLocation/RelativeRotation). Pawn bone poses are stale here (our own body is never
// rendered), so nothing is measured off the pawn.
function int CalibrateModel(Actor A)
{
	local coords C;
	local GunCal G;
	local vector Ctr, Up, BoneFwd, BoneUp, TX;
	local plane Sphere;
	local rotator RR;

	C = A.GetBoneCoords('tip');
	Sphere = A.GetRenderBoundingSphere();
	Ctr.X = Sphere.X; Ctr.Y = Sphere.Y; Ctr.Z = Sphere.Z;
	Ctr = (Ctr - A.Location) << A.Rotation;
	G.Cls = A.Class;
	RR = A.default.RelativeRotation;
	G.GripL = -(A.default.RelativeLocation << RR);
	// UT's convention: in the hand bone's space a weapon points down -X with its top towards -Z, and each
	// attachment's RelativeRotation maps its model into that space (AR/Shock/Link: Pitch 180 -> +X/+Z;
	// Redeemer: Yaw 270, Roll 180 -> along Y). So the barrel and up in model space are:
	BoneFwd = Normal(vect(-1,0,0) << RR);
	BoneUp = Normal(vect(0,0,-1) << RR);
	G.Xb = BoneFwd;
	if ( C.Origin != A.Location && VSize(C.Origin) > 0 && VSize(((C.Origin - A.Location) << A.Rotation) - Ctr) > 6 )
	{
		G.TipL = (C.Origin - A.Location) << A.Rotation;
		// prefer the muzzle bone's own axis (exact barrel), signed to agree with the convention
		TX = Normal(C.XAxis << A.Rotation);
		if ( (TX dot BoneFwd) < 0 )
			TX = -TX;
		if ( (TX dot BoneFwd) > 0.7 )
			G.Xb = TX;
	}
	else
		G.TipL = Ctr + G.Xb * Sphere.W * 0.8;   // no usable muzzle bone: front of the bounds
	Up = BoneUp - G.Xb * (BoneUp dot G.Xb);
	if ( VSize(Up) < 0.3 )
		Up = vect(0,0,1) - G.Xb * G.Xb.Z;
	G.Zb = Normal(Up);
	G.Yb = G.Zb cross G.Xb;
	if ( IsFlipped(A.Class) )
	{
		G.Zb = -G.Zb;
		G.Yb = -G.Yb;
	}
	GunCals[GunCals.Length] = G;
	Log("UT2004VR: calibrated "$A.Class$" tip="$G.TipL$" grip="$G.GripL$" centre="$Ctr$" barrel="$G.Xb$" up="$G.Zb, 'UT2004VR');
	return GunCals.Length - 1;
}

// debug: where do beam/bolt effects start, relative to the muzzle? (each new one logged once)
function LogNewEffects()
{
	local Actor A;
	local vector M, D, X, Y, Z;

	if ( Pawn == None || !GetMuzzle(M) )
		return;
	GetAxes(Rotation, X, Y, Z);
	foreach DynamicActors(class'Actor', A)
	{
		if ( A.Tag == 'VRSeen' )
			continue;
		if ( (A.Instigator == Pawn || (Pawn.Weapon != None && A.Owner == Pawn.Weapon))
			&& (A.IsA('xEmitter') || A.IsA('Emitter') || A.IsA('Projectile')) )
		{
			A.Tag = 'VRSeen';
			D = A.Location - M;
			Log("VR effect "$A.Class$" from "$Pawn.Weapon.Class$": "$(D dot X)$" fwd, "$(D dot Y)$" right, "$(D dot Z)$" up of the muzzle", 'UT2004VR');
		}
	}
}

// debug: how far is the real muzzle bone from the aim line through the hand? (should stay ~0 when rolling)
function LogGunError(Weapon W)
{
	local coords C;
	local vector A, P;
	local float Along;

	if ( GunModel == None )
		return;
	C = GunModel.GetBoneCoords('tip');
	A = vector(Rotation);
	P = C.Origin - GunTip();
	Along = P dot A;
	Log("VR gun: "$W.Class.Name$" natural handle "$((GunHandleW - GunHandW) << Rotation)$" from the hand (aim axes), muzzle "$Along$" ahead, roll "$(Rotation.Roll & 65535), 'UT2004VR');
}

// Draw the weapon's complete third-person model in the hand (the first-person meshes are hollow on the
// sides a flat game never shows, and oversized), aligned so its barrel lies on the aim line.
function UpdateGun()
{
	local Weapon W;
	local Actor A;
	local vector X, Y, Z, Xw, Yw, Zw, TipW, HandW, HandleL, O;
	local GunCal G;
	local coords TipC;

	if ( bScopeOn )
		HideLens();
	bScopeOn = false;
	if ( Pawn == None )
		return;
	W = Pawn.Weapon;
	if ( ShownWeapon != W )
	{
		if ( ShownWeapon != None )
		{
			ShownWeapon.bHidden = true;
			ShownWeapon.SetDrawScale(ShownWeapon.Default.DrawScale);
		}
		ShownWeapon = W;
		ShownSince = Level.TimeSeconds;
		bGunCalibrated = false;
		CurCal = -1;
	}
	if ( W == None )
		return;
	A = W.ThirdPersonActor;
	if ( GunModel != None && GunModel != A )
		GunModel.bHidden = true;
	GunModel = A;
	if ( A == None )
		return;
	if ( !GunActive() )
	{
		UpdateLaser(false, vect(0,0,0), vect(1,0,0));
		A.bHidden = true;
		W.bHidden = true;
		W.SetDrawScale(W.Default.DrawScale);
		return;
	}
	Handedness = 0;   // no screen-space left/right offsets for effects and projectiles
	W.Hand = 0;
	// SniperFire's Hand-0 branch starts the bolt at the body (Location + EffectOffset.X along the aim); its
	// right-handed branch goes through CalcDrawOffset, which VRPawn points at the muzzle. Instant-hit only,
	// so no projectile offsets come into play.
	if ( W.IsA('SniperRifle') )
		W.Hand = 1;

	if ( CurCal < 0 )
	{
		CurCal = FindCal(A.Class);
		if ( CurCal < 0 )
		{
			if ( A.Base != None )
			{
				Pawn.DetachFromBone(A);
				A.SetBase(None);
			}
			if ( Level.TimeSeconds - ShownSince > 0.3 )
				CurCal = CalibrateModel(A);
		}
	}
	// behind view: the gun in the character's hand, where UT hangs it (the muzzle, laser and shots come from there)
	if ( IsBehindOnFoot() && CurCal >= 0 )
	{
		if ( !bTPGun || A.Base != Pawn )
		{
			W.AttachToPawn(Pawn);
			bTPGun = true;
		}
	}
	else
	{
		bTPGun = false;
		if ( A.Base != None )
		{
			Pawn.DetachFromBone(A);
			A.SetBase(None);
		}
	}
	A.bOnlyDrawIfAttached = false;   // set on every InventoryAttachment; we hold it detached
	A.bUseLightingFromBase = false;
	bGunCalibrated = CurCal >= 0;
	A.bHidden = !bGunCalibrated;
	if ( !bGunCalibrated )
		return;
	G = GunCals[CurCal];

	if ( bKeyboardMouse )
		GetAxes(CleanAim(Rotation), X, Y, Z);
	else
		GetAxes(Rotation, X, Y, Z);
	// model axes such that its barrel frame lands on the aim frame
	Xw = G.Xb.X * X + G.Yb.X * Y + G.Zb.X * Z;
	Yw = G.Xb.Y * X + G.Yb.Y * Y + G.Zb.Y * Z;
	Zw = G.Xb.Z * X + G.Yb.Z * Y + G.Zb.Z * Z;
	// the handle (where the model hangs from a hand bone in third person, moved by the per-weapon VRGrip
	// offset) sits at the hand, so the gun turns around its handle; the barrel stays parallel to the aim
	if ( bTPGun )
	{
		// hanging from the hand bone: the model's own axes (UT's animation aims the arm); shots still go along
		// your aim from its muzzle
		GetAxes(A.Rotation, Xw, Yw, Zw);
		HandW = A.Location;
	}
	else
	{
		O = GripOffsetFor(W);
		HandleL = G.GripL - (O.X * G.Xb + O.Y * G.Yb + O.Z * G.Zb);
		HandW = GunTip() + GunOffset.X * X + GunOffset.Y * Y + GunOffset.Z * Z;
		A.SetRotation(OrthoRotation(Xw, Yw, Zw));
		A.SetLocation(HandW - (HandleL.X * Xw + HandleL.Y * Yw + HandleL.Z * Zw));
		ApplyRecoil(W, A, HandW, X, Z, Xw, Yw, Zw);
	}
	TipW = A.Location + G.TipL.X * Xw + G.TipL.Y * Yw + G.TipL.Z * Zw;
	if ( bTPGun )
	{
		// the model's own muzzle bone as rendered in the hand (its actor transform lags/differs while attached)
		TipC = A.GetBoneCoords('tip');
		if ( VSize(TipC.Origin) > 0 && VSize(TipC.Origin - Pawn.Location) < 200 )
			TipW = TipC.Origin;
		if ( bDebugLog && Level.TimeSeconds > NextCrossLog )
		{
			NextCrossLog = Level.TimeSeconds + 1.0;
			Log("UT2004VR: behind-view gun "$A.Class.Name$" base "$A.Base$" bone "$A.AttachmentBone$" muzzle "$((TipW - Pawn.Location) << Pawn.Rotation)$" (pawn axes) tip bone "$((TipC.Origin - Pawn.Location) << Pawn.Rotation), 'UT2004VR');
		}
	}
	GunTarget = TipW;
	GunTargetPawnLoc = Pawn.Location;
	GunHandW = HandW;
	GunHandleW = A.Location + G.GripL.X * Xw + G.GripL.Y * Yw + G.GripL.Z * Zw;
	UpdateLaser(true, TipW, X);
	UpdateScope(TipW, X, Y, Z);

	// Shield Gun alt-fire: the first-person shield is only a Canvas overlay; the third-person one is
	// owner-invisible and trails the body (PHYS_Trailer). Show that one, held in front of the gun.
	if ( ShieldAttachment(A) != None && ShieldAttachment(A).ShieldEffect3rd != None )
		HoldShield(ShieldAttachment(A).ShieldEffect3rd, TipW, X);

	// The first-person weapon is not drawn, but ShockRifle/LinkGun.GetEffectStart() read its 'tip' bone
	// (minus 15 uu along it) for beams. Keep it rendered at 1/1000 scale (so its bones stay posed) with
	// its tip 15 uu ahead of our muzzle: the beam then starts exactly at the muzzle.
	W.bHidden = false;
	if ( W.DrawScale != W.Default.DrawScale * 0.001 )
		W.SetDrawScale(W.Default.DrawScale * 0.001);
	W.SetRotation(Rotation);
	W.SetLocation(TipW + X * 15);
}

// the recoil of the shots fired since the last tick (see RecoilKick): the gun (axes Xw, Yw, Zw, placed with its
// handle at HandW) is pushed back along the aim X and turned muzzle-up about the handle
function ApplyRecoil(Weapon W, Actor A, vector HandW, vector X, vector Z, out vector Xw, out vector Yw, out vector Zw)
{
	local int m, i;
	local WeaponFire F;
	local float Dt, Amt, Ca, Sa, cx, cz;
	local vector L;

	if ( RecoilScale <= 0 )
		return;
	if ( W != RecoilWeapon )
	{
		RecoilWeapon = W;
		RecoilAmt = 0;
		for ( m = 0; m < 2; m++ )
		{
			F = W.GetFireMode(m);
			if ( F != None )
				RecoilNFT[m] = F.NextFireTime;
		}
	}
	for ( m = 0; m < 2; m++ )
	{
		F = W.GetFireMode(m);
		if ( F == None )
			continue;
		// (starting to fire also moves it on, to now + PreFireTime: not a shot)
		if ( F.NextFireTime > RecoilNFT[m] + 0.001 && F.NextFireTime > Level.TimeSeconds + F.PreFireTime + 0.0005 )
		{
			// a shot: this mode's kick (the list, else from its fire rate: slow guns kick hard)
			RecoilBack = FClamp(F.FireRate * 10, 1, 12);
			RecoilUp = RecoilBack * 1.3;
			for ( i = 0; i < Recoils.Length; i++ )
				if ( F.IsA(Recoils[i].Fire) )
				{
					RecoilBack = Recoils[i].Back;
					RecoilUp = Recoils[i].Up;
					break;
				}
			// rapid fire adds up a little, never past one and a half kicks
			RecoilAmt = FMin(RecoilAmt + 1.0, 1.5);
			if ( bDebugLog )
				Log("UT2004VR: recoil "$F.Class.Name$" back "$RecoilBack$" cm up "$RecoilUp$" deg amount "$RecoilAmt, 'UT2004VR');
		}
		RecoilNFT[m] = F.NextFireTime;
	}
	if ( Level.TimeSeconds != RecoilAt )
	{
		Dt = FClamp(Level.TimeSeconds - RecoilAt, 0, 0.1);
		RecoilAt = Level.TimeSeconds;
		// the kick springs back over RecoilReturn; the shown gun follows it within ~20 ms (no one-frame jump)
		RecoilAmt *= Exp(-Dt / FMax(RecoilReturn / 3, 0.01));
		RecoilShown += (RecoilAmt - RecoilShown) * FMin(1, Dt / 0.02);
	}
	Amt = RecoilShown * RecoilScale;
	if ( Amt < 0.001 )
		return;
	Ca = Cos(RecoilUp * Amt * 0.0174533);
	Sa = Sin(RecoilUp * Amt * 0.0174533);
	// muzzle up about the gun's right axis through the handle: X -> X cos + Z sin, Z -> Z cos - X sin
	L = A.Location - HandW;
	cx = L dot X; cz = L dot Z;
	L += (cx * (Ca - 1) - cz * Sa) * X + (cx * Sa + cz * (Ca - 1)) * Z;
	cx = Xw dot X; cz = Xw dot Z;
	Xw += (cx * (Ca - 1) - cz * Sa) * X + (cx * Sa + cz * (Ca - 1)) * Z;
	cx = Yw dot X; cz = Yw dot Z;
	Yw += (cx * (Ca - 1) - cz * Sa) * X + (cx * Sa + cz * (Ca - 1)) * Z;
	cx = Zw dot X; cz = Zw dot Z;
	Zw += (cx * (Ca - 1) - cz * Sa) * X + (cx * Sa + cz * (Ca - 1)) * Z;
	A.SetRotation(OrthoRotation(Xw, Yw, Zw));
	A.SetLocation(HandW + L - X * (RecoilBack * Amt * UUPerMeter / 100));
}

function UpdateLaser(bool bShow, vector Start, vector Dir, optional bool bHasEnd, optional vector ForcedEnd, optional bool bForcedHit)
{
	local vector HitLoc, HitNorm, End;
	local Actor HitActor;
	local float F;

	if ( !bShow || !bLaser || bMenuOpen )
	{
		if ( Laser != None ) Laser.bHidden = true;
		if ( LaserDot != None ) LaserDot.bHidden = true;
		return;
	}
	if ( Laser == None )
		Laser = Spawn(class'VRLaser', self,, Start, rotator(Dir));
	if ( LaserDot == None )
	{
		LaserDot = Spawn(class'VRArcDot', self,, Start);
		if ( LaserDot != None )
		{
			LaserDot.Texture = Texture'EpicParticles.Flares.SoftFlare';
			LaserDot.Style = STY_Additive;
		}
	}
	// hidden while firing, fades back in over LaserFadeIn seconds afterwards
	if ( bFire != 0 || bAltFire != 0 || (Pawn != None && Pawn.Weapon != None && Pawn.Weapon.IsFiring()) )
		LaserLastFire = Level.TimeSeconds;
	if ( LaserFadeIn > 0 )
		F = FClamp((Level.TimeSeconds - LaserLastFire) / LaserFadeIn, 0, 1);
	else
		F = 1;
	F *= FClamp(LaserBrightness, 0, 1);
	End = Start + Dir * LaserRange;
	if ( bHasEnd )
	{
		// the caller traced it (vehicles: past their own hull and guns)
		End = ForcedEnd;
		if ( bForcedHit )
			HitActor = self;
	}
	else
	{
		HitActor = Trace(HitLoc, HitNorm, End, Start, true);
		if ( HitActor != None && HitActor != Pawn )
			End = HitLoc;
	}
	if ( Laser != None )
	{
		Laser.bHidden = F <= 0.01;
		Laser.mColorRange[0].R = byte(255 * F);
		Laser.mColorRange[0].G = byte(36 * F);
		Laser.mColorRange[0].B = byte(36 * F);
		Laser.mColorRange[1] = Laser.mColorRange[0];
		Laser.mSizeRange[0] = LaserWidth;
		Laser.mSizeRange[1] = LaserWidth;
		Laser.SetLocation(Start);
		Laser.SetRotation(rotator(Dir));
		Laser.mSpawnVecA = End;
	}
	if ( LaserDot != None )
	{
		LaserDot.bHidden = HitActor == None || F <= 0.01;
		LaserDot.ScaleGlow = F;
		LaserDot.SetLocation(End - Dir * 2);
		LaserDot.SetDrawScale(FMax(0.02, VSize(End - VRHeadWorld) * LaserDotSize));
	}
}

// ---------------------------------------------------------------------------
// Scope: UT zooms by narrowing the whole view (FOVAngle), which in a headset would swing the world with every head
// movement. Instead the zoomed view goes into a small round lens: rendered from the muzzle along the barrel, so
// its centre is where the shot goes; magnified at least ScopeMinZoom, more as UT's zoom closes in.
// ---------------------------------------------------------------------------
function AdjustView(float DeltaTime)
{
	LastAdjustView = Level.TimeSeconds;
	Super.AdjustView(DeltaTime);
}

function bool IsZoomed()
{
	return bZooming || FOVAngle < DefaultFOV - 1;
}

function UpdateScope(vector TipW, vector X, vector Y, vector Z)
{
	local float D, A, Mag;
	local vector HZ, CY, CZ;
	if ( !bScope || !IsZoomed() || bMenuOpen )
		return;
	ScopeCamLoc = TipW + X * 20;
	// the lens is a disc in the scene facing along your aim, its top level with the world (keyboard mode) or the gun's
	// top (controller mode); the picture in it uses the same frame, so it lines up with the world around it
	if ( bKeyboardMouse )
		HZ = vect(0,0,1);
	else
		HZ = Z;
	CZ = HZ - X * (HZ dot X);
	if ( VSize(CZ) < 0.2 )
		CZ = Z;   // aiming straight up/down: the gun's up
	CZ = Normal(CZ);
	CY = Normal(CZ cross X);
	ScopeCamRot = OrthoRotation(X, CY, CZ);
	ScopeReticleRoll = 0;
	if ( bKeyboardMouse )
	{
		ScopeLensW = VRHeadWorld + X * ScopeKBMDistance * UUPerMeter;
		ScopeLensR = ScopeKBMDiameter * 0.5 * UUPerMeter;
	}
	else
	{
		ScopeLensW = GunHandleW + (X * ScopeOffset.X + Y * ScopeOffset.Y + Z * ScopeOffset.Z) * UUPerMeter;
		ScopeLensR = ScopeDiameter * 0.5 * UUPerMeter;
	}
	D = FMax(VSize(ScopeLensW - VRHeadWorld), 1);
	A = 2 * Atan(ScopeLensR, D) * 180.0 / 3.14159265;          // how wide the lens looks
	Mag = FMax(ScopeMinZoom, DefaultFOV / FMax(FOVAngle, 1));
	ScopeViewFOV = FClamp(A / Mag, 0.3, 60);
	if ( ScopeTex == None )
	{
		ScopeTex = ScriptedTexture(Level.ObjectPool.AllocateObject(class'ScriptedTexture'));
		ScopeTex.Client = self;
		ScopeTex.SetSize(ScopeRes, ScopeRes);
	}
	if ( ScopeMat == None )
		ScopeMat = MakeScopeMaterial();
	bScopeOn = ScopeTex != None;
	PlaceLens(X, CY, CZ);
}

// the lens discs: the picture, and the dark rim just behind it
function PlaceLens(vector X, vector Y, vector Z)
{
	local FinalBlend FB;
	if ( LensPic == None )
	{
		LensPic = Spawn(class'VRLensActor', self);
		LensRim = Spawn(class'VRLensActor', self);
		if ( LensRim != None )
		{
			FB = new(None) class'FinalBlend';
			FB.Material = Texture'VRScopeRing';
			FB.FrameBufferBlending = FB_AlphaBlend;
			LensRim.Skins[0] = FB;
		}
	}
	if ( LensPic == None || LensRim == None )
		return;
	LensPic.Skins[0] = ScopeMat;
	LensPic.SetDrawScale(ScopeLensR / 100.0);
	LensRim.SetDrawScale(ScopeLensR * 1.06 / 100.0);
	LensPic.SetLocation(ScopeLensW);
	LensRim.SetLocation(ScopeLensW + X * 0.3);
	LensPic.SetRotation(OrthoRotation(X, Y, Z));
	LensRim.SetRotation(OrthoRotation(X, Y, Z));
	LensPic.bHidden = false;
	LensRim.bHidden = false;
}

function HideLens()
{
	if ( LensPic != None ) LensPic.bHidden = true;
	if ( LensRim != None ) LensRim.bHidden = true;
}

function Material MakeScopeMaterial()
{
	local Combiner C;
	local FinalBlend FB;
	C = new(None) class'Combiner';
	C.Material1 = ScopeTex;
	C.Material2 = Texture'VRScopeMask';
	C.CombineOperation = CO_Use_Color_From_Material1;
	C.AlphaOperation = AO_Use_Alpha_From_Material2;
	FB = new(None) class'FinalBlend';
	FB.Material = C;
	FB.FrameBufferBlending = FB_AlphaBlend;
	return FB;
}

// the scope's own render (VRMirrorInteraction triggers it right before the eyes)
function RenderScope(ScriptedTexture Tex)
{
	local float c, w, g, L;
	local int i;
	if ( Pawn == None )
		return;
	// not in the scope: the laser and its dot (magnified, they cover the target; the reticle marks it), the gun,
	// UT's tiny first-person weapon ahead of the muzzle, and what hangs on them (the Lightning Gun's sparks)
	ScopeHidden.Length = 0;
	ScopeHide(Laser);
	ScopeHide(LaserDot);
	ScopeHide(LensPic);
	ScopeHide(LensRim);
	if ( Pawn.Weapon != None )
	{
		ScopeHide(Pawn.Weapon);
		ScopeHideAttached(Pawn.Weapon);
		ScopeHide(Pawn.Weapon.ThirdPersonActor);
		ScopeHideAttached(Pawn.Weapon.ThirdPersonActor);
		if ( SniperRifle(Pawn.Weapon) != None )
			ScopeHide(SniperRifle(Pawn.Weapon).chargeEmitter);
		if ( SniperAttachment(Pawn.Weapon.ThirdPersonActor) != None )
			ScopeHide(SniperAttachment(Pawn.Weapon.ThirdPersonActor).charge);
	}
	Tex.DrawPortal(0, 0, Tex.USize, Tex.VSize, Pawn, ScopeCamLoc, ScopeCamRot, ScopeViewFOV, true);
	for ( i = 0; i < ScopeHidden.Length; i++ )
		if ( ScopeHidden[i] != None )
			ScopeHidden[i].bHidden = false;
	ScopeHidden.Length = 0;

	// a duplex reticle turned with the gun: thick outer posts, thin lines at the centre
	c = Tex.USize * 0.5;
	w = FMax(1, Tex.USize / 256);
	g = Tex.USize * 0.03;
	L = c;
	for ( i = 0; i < 4; i++ )
	{
		ReticleLine(Tex, c, ScopeReticleRoll + i * 1.5707963, g, L, w);
		ReticleLine(Tex, c, ScopeReticleRoll + i * 1.5707963, L * 0.45, L, w * 4);
	}
}

function ScopeHide(Actor A)
{
	if ( A == None || A.bHidden )
		return;
	A.bHidden = true;
	ScopeHidden[ScopeHidden.Length] = A;
}

function ScopeHideAttached(Actor A)
{
	local int i;
	if ( A == None )
		return;
	for ( i = 0; i < A.Attached.Length; i++ )
		ScopeHide(A.Attached[i]);
}

// one arm of the reticle from the centre c, at angle Ang (radians, clockwise from up), R0..R1 pixels out, W wide:
// square dots along it (a canvas tile can't be rotated); a plain bar when it's axis-aligned
function ReticleLine(ScriptedTexture Tex, float c, float Ang, float R0, float R1, float W)
{
	local float DX, DY, R, Step;
	local color K;
	K = HudColor(0, 0, 0);
	DX = Sin(Ang);
	DY = -Cos(Ang);
	if ( Abs(DX) < 0.004 || Abs(DY) < 0.004 )
	{
		if ( Abs(DX) < 0.004 )
			Tex.DrawTile(c - W * 0.5, FMin(c + DY * R0, c + DY * R1), W, R1 - R0, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
		else
			Tex.DrawTile(FMin(c + DX * R0, c + DX * R1), c - W * 0.5, R1 - R0, W, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
		return;
	}
	Step = FMax(1, W * 0.7);
	for ( R = R0; R <= R1; R += Step )
		Tex.DrawTile(c + DX * R - W * 0.5, c + DY * R - W * 0.5, W, W, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
}


// debug: UT's message kinds at once (first blood, a pickup, a multi kill, a kill line, a chat line)
exec function VRTestMessages()
{
	ReceiveLocalizedMessage(class'FirstBloodMessage', 0, PlayerReplicationInfo);
	ReceiveLocalizedMessage(class'PickupMessagePlus', 0, None, None, class'XWeapons.FlakCannonPickup');
	ReceiveLocalizedMessage(class'MultiKillMessage', 1, PlayerReplicationInfo);
	TeamMessage(PlayerReplicationInfo, "Poppamies was killed by a test", 'DeathMessage');
	TeamMessage(PlayerReplicationInfo, "hello from VR", 'Say');
}

// debug: give and hold a weapon (TestExec lines don't reach the cheat manager), e.g. VRGiveWeapon XWeapons.SniperRifle
exec function VRGiveWeapon(string ClassName)
{
	local class<Weapon> C;
	local Weapon W;
	if ( Pawn == None || Level.NetMode != NM_Standalone )
		return;
	C = class<Weapon>(DynamicLoadObject(ClassName, class'Class'));
	if ( C == None )
		return;
	W = Weapon(Pawn.FindInventoryType(C));
	if ( W == None )
	{
		W = Spawn(C,,, Pawn.Location);
		if ( W != None )
		{
			W.GiveTo(Pawn);
			W.ConsumeAmmo(0, -50);   // some ammo
		}
	}
	if ( W != None )
	{
		Pawn.PendingWeapon = W;
		if ( Pawn.Weapon != None )
			Pawn.Weapon.PutDown();
		else
			Pawn.ChangedWeapon();
	}
	Log("UT2004VR: gave "$W, 'UT2004VR');
}

// debug: press a controller button for 0.3 s, as the proxy would report it: use, jump, next, prev, dodge, crouch
exec function VRTapBtn(string B)
{
	TapBtn = Caps(B);
	TapBtnUntil = Level.TimeSeconds + 0.3;
	SetTapBtn(true);
}

function SetTapBtn(bool bOn)
{
	switch ( TapBtn )
	{
	case "USE": bBtnUse = bOn; break;
	case "JUMP": bBtnJump = bOn; break;
	case "NEXT": bBtnNext = bOn; break;
	case "PREV": bBtnPrev = bOn; break;
	case "DODGE": bBtnDodge = bOn; break;
	case "CROUCH": bBtnCrouch = bOn; break;
	}
}

// debug: hold the right stick at "x y" for 3 s (where the warhead steering reads it)
exec function VRStick(string XY)
{
	local array<string> P;
	if ( Split(XY, " ", P) >= 2 )
	{
		DebugStickX = float(P[0]);
		DebugStickY = float(P[1]);
		DebugStickUntil = Level.TimeSeconds + 3;
	}
}

// debug: hold alt-fire for some seconds, as the right mouse button does
exec function VRAltHold(float Secs)
{
	if ( Pawn == None || Pawn.Weapon == None )
		return;
	AltHoldUntil = Level.TimeSeconds + Secs;
	Pawn.Weapon.ClientStartFire(1);
	Log("UT2004VR: alt-fire held, zooming "$bZooming$" fov "$FOVAngle, 'UT2004VR');
}

// debug: UT's zoom, as the Lightning Gun's alt-fire starts it (again: stop)
exec function VRZoom()
{
	if ( IsZoomed() )
		EndZoom();
	else
		StartZoom();
	Log("UT2004VR: zoom "$bZooming$" fov "$FOVAngle, 'UT2004VR');
}

function HoldShield(Actor E, vector TipW, vector X)
{
	E.bOwnerNoSee = false;
	if ( E.Physics != PHYS_None )
		E.SetPhysics(PHYS_None);
	if ( E.Base != None )
		E.SetBase(None);
	E.SetLocation(TipW + X * 12);
	E.SetRotation(Rotation);
}

// Alyx has no aim assist: the shot goes exactly where the gun points
function rotator AdjustAim(FireProperties FiredAmmunition, vector projStart, int aimerror)
{
	if ( GunActive() )
		return Rotation;
	return Super.AdjustAim(FiredAmmunition, projStart, aimerror);
}

function VRWeaponInput()
{
	if ( Pawn == None )
		return;
	if ( bBtnFire )
		bFire = 1;
	else
		bFire = 0;
	if ( bBtnAlt )
		bAltFire = 1;
	else
		bAltFire = 0;
	if ( bBtnFire && !bOldFire )
		Fire(0);
	else if ( !bBtnFire && bOldFire && Pawn.Weapon != None )
		Pawn.Weapon.ClientStopFire(0);
	if ( bBtnAlt && !bOldAlt )
		AltFire(0);
	else if ( !bBtnAlt && bOldAlt && Pawn.Weapon != None )
		Pawn.Weapon.ClientStopFire(1);
	if ( bBtnNext && !bOldNext )
		CycleWeapon(1);
	if ( bBtnPrev && !bOldPrev )
		CycleWeapon(-1);
	// the right stick click: use (enter the vehicle or turret you stand at, as the Use key does)
	if ( bBtnUse && !bOldUse )
	{
		Log("UT2004VR: use (controller)", 'UT2004VR');
		Use();
	}
	bOldUse = bBtnUse;
	bOldFire = bBtnFire;
	bOldAlt = bBtnAlt;
	bOldNext = bBtnNext;
	bOldPrev = bBtnPrev;
}

// controller mode in a vehicle or turret: the trigger and grip fire, A / B (next / previous weapon) change seats
// (Assault's vehicles: UT's own next / previous: the fighter's target, the turret group's next turret), the left
// stick click sounds the horn, the right stick click (use) gets out. Driving is in PlayerDriving.
function VRVehicleButtons()
{
	if ( bBtnFire )
		bFire = 1;
	else
		bFire = 0;
	if ( bBtnAlt )
		bAltFire = 1;
	else
		bAltFire = 0;
	// UT stops the vehicle's guns itself once bFire / bAltFire are 0
	if ( bBtnFire && !bOldVehFire )
		Fire(0);
	if ( bBtnAlt && !bOldVehAlt )
		AltFire(0);
	if ( bBtnNext && !bOldVehNext )
		NextWeapon();
	if ( bBtnPrev && !bOldVehPrev )
		PrevWeapon();
	if ( bBtnJump && !bOldVehJump )
	{
		Log("UT2004VR: horn (controller) "$Pawn.Class.Name, 'UT2004VR');
		PlayVehicleHorn(0);
	}
	if ( bBtnUse && !bOldUse )
	{
		Log("UT2004VR: use (controller): leaving "$Pawn.Class.Name, 'UT2004VR');
		Use();
	}
	bOldVehFire = bBtnFire;
	bOldVehAlt = bBtnAlt;
	bOldVehNext = bBtnNext;
	bOldVehPrev = bBtnPrev;
	bOldVehJump = bBtnJump;
	bOldUse = bBtnUse;
	// on foot again, the same press must not count there as a new one
	bOldFire = bBtnFire;
	bOldAlt = bBtnAlt;
	bOldNext = bBtnNext;
	bOldPrev = bBtnPrev;
	bOldJump = bBtnJump;
}

// a stick axis with a small dead zone, rescaled so it still reaches 1
function float StickAxis(float V)
{
	if ( Abs(V) < 0.15 )
		return 0;
	if ( V > 0 )
		return (V - 0.15) / 0.85;
	return (V + 0.15) / 0.85;
}

// controller mode in a vehicle: the left stick drives (forward / back) and steers (left / right; hovering and flying
// vehicles strafe), as W/S and A/D do; the left trigger (dodge) jumps or rises, the grip (crouch) ducks or descends,
// as Space and C do (a space fighter: trigger + stick left / right rolls, the grip levels the wings)
function VRStickDrive()
{
	if ( Level.TimeSeconds < DebugStickUntil )
	{
		StickMX = DebugStickX;
		StickMY = DebugStickY;
	}
	aForward = StickAxis(StickMY) * 6000;
	aStrafe = StickAxis(StickMX) * 6000;
	aUp = 0;
	if ( bBtnDodge )
		aUp = 6000;
	else if ( bBtnCrouch )
		aUp = -6000;
	if ( bBtnCrouch )
		bDuck = 1;
	else
		bDuck = 0;
	if ( bBtnDodge && !bOldVehDodge )
		bPressedJump = true;
	bOldVehDodge = bBtnDodge;
	if ( bDebugLog && (aForward != 0 || aStrafe != 0 || aUp != 0) && Level.TimeSeconds > NextCrossLog )
	{
		NextCrossLog = Level.TimeSeconds + 0.5;
		Log("UT2004VR: drive stick "$StickMX$","$StickMY$" -> forward "$aForward$" strafe "$aStrafe$" up "$aUp, 'UT2004VR');
	}
}

state PlayerDriving
{
	function PlayerMove(float DeltaTime)
	{
		if ( VRActive() && !bKeyboardMouse && Vehicle(Pawn) != None )
			VRStickDrive();
		Super.PlayerMove(DeltaTime);
	}
}

// Assault's space fighters: the left stick is the throttle (forward / back) and strafes, the right stick pitches
// and yaws as the mouse does (FighterSteer); A / B pick the next / previous target, the trigger and grip fire
state PlayerSpaceFlying
{
	function PlayerMove(float DeltaTime)
	{
		if ( VRActive() && !bKeyboardMouse && Vehicle(Pawn) != None )
		{
			VRStickDrive();
			if ( Level.TimeSeconds < DebugStickUntil )
			{
				StickTX = DebugStickX;
				StickTY = DebugStickY;
			}
			aTurn += StickAxis(StickTX) * Abs(FighterSteer);
			aLookUp += StickAxis(StickTY) * FighterSteer;
			if ( bDebugLog && (StickTX != 0 || StickTY != 0) && Level.TimeSeconds > NextCineLog )
			{
				NextCineLog = Level.TimeSeconds + 0.5;
				Log("UT2004VR: fighter steer stick "$StickTX$","$StickTY$" -> aTurn "$aTurn$" aLookUp "$aLookUp$" rot "$Pawn.Rotation, 'UT2004VR');
			}
		}
		Super.PlayerMove(DeltaTime);
	}
}

// UT's NextWeapon/PrevWeapon skip inventory group 0 (Redeemer, Ion Painter: keyboard key 0), which a
// controller has no way to reach. Cycle through every carried weapon with ammo, by group, group 0 last.
function CycleWeapon(int Dir)
{
	local Inventory Inv;
	local array<Weapon> L;
	local Weapon W;
	local int i, j, Cur, Ki, Kj;

	if ( Pawn == None )
		return;
	if ( Vehicle(Pawn) != None )
	{
		VehicleSeatCycle(Dir);
		return;
	}
	for ( Inv = Pawn.Inventory; Inv != None; Inv = Inv.Inventory )
	{
		W = Weapon(Inv);
		if ( bCalibGun && W != None )
			Log("VR cycle: "$W.Class.Name$" group="$W.InventoryGroup$" offset="$W.GroupOffset$" hasammo="$W.HasAmmo()$" ammo="$W.AmmoClass[0]$"/"$W.AmmoClass[1], 'UT2004VR');
		// skip empty guns, but not ammo-less ones (Shield Gun: HasAmmo() is false without an ammo class)
		if ( W == None || (W != Pawn.Weapon && !W.HasAmmo() && (W.AmmoClass[0] != None || W.AmmoClass[1] != None)) )
			continue;
		// insertion sort by (group, 0 last), then by InventoryGroup position
		Ki = W.InventoryGroup;
		if ( Ki == 0 ) Ki = 100;
		Ki = Ki * 1000 + W.GroupOffset;
		for ( i = 0; i < L.Length; i++ )
		{
			Kj = L[i].InventoryGroup;
			if ( Kj == 0 ) Kj = 100;
			Kj = Kj * 1000 + L[i].GroupOffset;
			if ( Ki < Kj )
				break;
		}
		L.Insert(i, 1);
		L[i] = W;
	}
	if ( L.Length < 2 )
		return;
	Cur = -1;
	for ( j = 0; j < L.Length; j++ )
		if ( L[j] == Pawn.Weapon || L[j] == Pawn.PendingWeapon )
			Cur = j;
	j = Cur + Dir;
	if ( j >= L.Length ) j = 0;
	if ( j < 0 ) j = L.Length - 1;
	if ( L[j] == Pawn.Weapon )
		return;
	// switch like UT's NextWeapon does (GetWeapon would refuse the Shield Gun for "no ammo")
	Pawn.PendingWeapon = L[j];
	if ( Pawn.Weapon != None )
		Pawn.Weapon.PutDown();
	else
		Pawn.ChangedWeapon();
}

function SetPawnClass(string inClass, string inCharacter)
{
	Super.SetPawnClass(inClass, inCharacter);
	PawnClass = class'VRPawn';
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------
event PlayerCalcView(out actor ViewActor, out vector CameraLocation, out rotator CameraRotation)
{
	if ( !VRActive() || Pawn == None || ViewTarget != Pawn || (bBehindView && Vehicle(Pawn) == None) )
	{
		Super.PlayerCalcView(ViewActor, CameraLocation, CameraRotation);
		if ( IsFreeView() )
		{
			// the desktop shows UT's camera (cinematic, waiting, spectating): the eyes go there too
			CineCamLoc = CameraLocation;
			CineCamRot = CameraRotation;
			bCineCam = true;
			if ( bDebugLog && Level.TimeSeconds > NextCineLog )
			{
				NextCineLog = Level.TimeSeconds + 1.0;
				Log("UT2004VR: cinematic camera "$CameraLocation$" rot "$CameraRotation$" eyes at "$VRHeadWorld$" rot "$VRHeadRot$" anchor "$CineAnchor$" head "$HeadPos$" anchored "$bCineAnchored, 'UT2004VR');

			}
		}
		return;
	}
	UpdateHeadWorld();
	ViewActor = Pawn;
	CameraLocation = VRHeadWorld;
	CameraRotation = VRHeadRot;
	// vehicle guns aim where this view looks (UT traces along it): your gaze, level (no roll)
	if ( Vehicle(Pawn) != None )
		CameraRotation.Roll = 0;
	CacheCalcView(ViewActor, CameraLocation, CameraRotation);
}

// in a vehicle the controller looks where you look, whatever the mouse does: vehicles that turn toward the view
// (Manta, Raptor) turn toward your gaze, and seats that keep the rotation relative to the vehicle get it converted
function GazeVehicleRotation()
{
	local rotator G;
	G = VRHeadRot;
	G.Roll = 0;
	if ( Vehicle(Pawn).bPCRelativeFPRotation )
		G = rotator(vector(G) << Pawn.Rotation);
	SetRotation(G);
}

// Guns that turn at a set rate (the Goliath cannon's "rubber band") turn slower in VR, where a glance moves the aim
// point at once: TurretSpeed. Guns UT snaps to the view stay instant unless InstantTurretSpeed is set (turns/s).
// Put back when you leave.
function TuneVehicleGuns()
{
	local int i;
	local array<ONSWeapon> L;
	local bool bKeep;

	if ( Vehicle(Pawn) != None && VRActive() )
	{
		if ( ONSVehicle(Pawn) != None )
			for ( i = 0; i < ONSVehicle(Pawn).Weapons.Length; i++ )
				L[L.Length] = ONSVehicle(Pawn).Weapons[i];
		else if ( ONSWeaponPawn(Pawn) != None )
			L[0] = ONSWeaponPawn(Pawn).Gun;
	}
	// still the same guns: nothing to do
	bKeep = L.Length == TunedGuns.Length;
	for ( i = 0; bKeep && i < L.Length; i++ )
		bKeep = L[i] == TunedGuns[i];
	if ( bKeep )
		return;
	for ( i = 0; i < TunedGuns.Length; i++ )
		if ( TunedGuns[i] != None )
		{
			TunedGuns[i].RotationsPerSecond = TunedRPS[i];
			TunedGuns[i].bInstantRotation = TunedInstant[i] != 0;
		}
	TunedGuns.Length = 0;
	TunedRPS.Length = 0;
	TunedInstant.Length = 0;
	for ( i = 0; i < L.Length; i++ )
	{
		if ( L[i] == None )
			continue;
		TunedGuns[TunedGuns.Length] = L[i];
		TunedRPS[TunedRPS.Length] = L[i].RotationsPerSecond;
		if ( L[i].bInstantRotation )
		{
			TunedInstant[TunedInstant.Length] = 1;
			if ( InstantTurretSpeed > 0 )
			{
				L[i].bInstantRotation = false;
				L[i].RotationsPerSecond = InstantTurretSpeed;
			}
		}
		else
		{
			TunedInstant[TunedInstant.Length] = 0;
			if ( TurretSpeed > 0 )
				L[i].RotationsPerSecond = TunedRPS[i] * TurretSpeed;
		}
		Log("UT2004VR: VR gun speed "$L[i].Class.Name$" "$TunedRPS[i]$" turns/s"$Mid(" (instant)", 0, 10 * TunedInstant[i])$" -> "$L[i].RotationsPerSecond$" instant "$L[i].bInstantRotation, 'UT2004VR');
	}
}

// ---------------------------------------------------------------------------
// Locomotion
// ---------------------------------------------------------------------------
function VRTurn(float DeltaTime)
{
	if ( bSmoothTurn )
	{
		if ( Abs(StickTX) > 0.2 )
		{
			PlayYaw += int(StickTX * SmoothTurnDegPerSec * 65536.0 / 360.0 * DeltaTime);
			BodyYaw += int(StickTX * SmoothTurnDegPerSec * 65536.0 / 360.0 * DeltaTime);
		}
		return;
	}
	if ( Abs(StickTX) > 0.7 && !bTurnLatched && !bAiming )
	{
		bTurnLatched = true;
		if ( StickTX > 0 )
		{
			PlayYaw += SnapTurnDegrees * 65536 / 360;
			BodyYaw += SnapTurnDegrees * 65536 / 360;
		}
		else
		{
			PlayYaw -= SnapTurnDegrees * 65536 / 360;
			BodyYaw -= SnapTurnDegrees * 65536 / 360;
		}
		BlinkUntil = Level.TimeSeconds + 0.05;
	}
	else if ( Abs(StickTX) < 0.3 )
		bTurnLatched = false;
}

// The eyes sit in front of and above the neck, so turning the head swings them in an arc, which a tracked headset
// position includes. When the headset loses its position (WMR: the cameras lose their fix, SteamVR reports
// "rotation only", field 12 of the head packet) the position freezes and the world stops shifting as you turn your
// head: then the arc is added (NeckForward / NeckUp, from a neck pivot; zero looking along the chair's forward, so
// the calibration holds), blended in and out over NeckBlendTime. BodyHeadPos is the head without the arc either
// way: the keyboard-mode gun sits on it, so turning your head doesn't move the gun.
function NeckModel(int Track)
{
	local vector Arc, ChairF, Up;
	local rotator R;
	local float Want, Dt;

	if ( bChairYawValid )
	{
		R.Yaw = ChairYaw;
		ChairF = vector(R);
		Up.Z = 1;
		Arc = Normal(HeadF) * NeckForward + Normal(HeadU) * NeckUp - ChairF * NeckForward - Up * NeckUp;
	}
	// 300 = TrackingResult_Fallback_RotationOnly; NeckModel=1 always, 0 never (2 = when the headset says so)
	Want = 0;
	if ( NeckModelMode == 1 || (NeckModelMode == 2 && Track == 300) )
		Want = 1;
	if ( (Want > 0) != bNeckModel )
	{
		bNeckModel = Want > 0;
		Log("UT2004VR: neck model "$Mid("offon", 3 * int(bNeckModel), 3)$" (headset tracking "$Track$")", 'UT2004VR');
	}
	Dt = Level.TimeSeconds - NeckBlendAt;
	NeckBlendAt = Level.TimeSeconds;
	if ( Dt < 0 || Dt > 0.5 || NeckBlendTime <= 0 )
		NeckBlend = Want;
	else if ( NeckBlend < Want )
		NeckBlend = FMin(Want, NeckBlend + Dt / NeckBlendTime);
	else
		NeckBlend = FMax(Want, NeckBlend - Dt / NeckBlendTime);

	BodyHeadPos = HeadPos - Arc * (1 - NeckBlend);
	HeadPos += Arc * NeckBlend;
}

// room-scale: move the pawn after the head, with collision; whatever is blocked stays as a head offset
function VRFollowHead()
{
	local vector Want, Before, Moved;

	if ( !bAnchorValid )
	{
		Anchor = HeadPos;
		Anchor.Z = 0;
		bAnchorValid = true;
	}
	Want = HeadPos - Anchor;
	Want.Z = 0;
	if ( VSize(Want) * UUPerMeter < 1.0 )
		return;
	Before = Pawn.Location;
	Pawn.Move(PlayToWorld(Want));
	Moved = Pawn.Location - Before;
	Moved.Z = 0;
	// convert what actually happened back into playspace meters
	Anchor += (Moved << PlayRot()) / UUPerMeter;
	Anchor.Z = 0;
}

function ShowArc(int Count)
{
	local int i;
	for ( i = Count; i < 32; i++ )
		if ( ArcDots[i] != None )
			ArcDots[i].bHidden = true;
	if ( Count == 0 && ArcTarget != None )
		ArcTarget.bHidden = true;
}

function PlaceDot(int i, vector Loc)
{
	if ( ArcDots[i] == None )
		ArcDots[i] = Spawn(class'VRArcDot', self,, Loc);
	if ( ArcDots[i] != None )
	{
		ArcDots[i].SetLocation(Loc);
		ArcDots[i].bHidden = false;
	}
}

function PlaceTarget(vector Loc, bool bValid)
{
	if ( ArcTarget == None )
		ArcTarget = Spawn(class'VRArcDot', self,, Loc);
	if ( ArcTarget == None )
		return;
	ArcTarget.SetLocation(Loc);
	ArcTarget.bHidden = false;
	if ( bValid )
		ArcTarget.SetDrawScale(0.35);
	else
		ArcTarget.SetDrawScale(0.12);
}

function VRTeleportAim()
{
	local vector P, V, NewP, HitLoc, HitNorm, Start, Dir;
	local actor HitActor;
	local int i;
	local float Dt;

	bTeleportValid = false;
	if ( bHandOK[1] != 0 )
		GetHandWorld(1, Start, Dir);
	else
	{
		Start = VRHeadWorld;
		Dir = vector(VRHeadRot);
	}
	P = Start;
	V = Dir * TeleportSpeed;
	Dt = 0.04;
	for ( i = 0; i < 60; i++ )
	{
		NewP = P + V * Dt;
		V.Z -= 1100 * Dt;
		HitActor = Trace(HitLoc, HitNorm, NewP, P, false);
		if ( HitActor != None )
		{
			if ( HitNorm.Z > 0.7 && VSize(HitLoc - BaseXY()) < TeleportMaxDist )
			{
				bTeleportValid = true;
				TeleportTarget = HitLoc;
			}
			PlaceTarget(HitLoc + HitNorm * 6, bTeleportValid);
			ShowArc(Min(i, 32));
			return;
		}
		if ( i < 32 )
			PlaceDot(i, NewP);
		P = NewP;
	}
	ShowArc(32);
	PlaceTarget(P, false);
}

function VRTeleportGo()
{
	local vector Dest;

	if ( !bTeleportValid || Pawn == None )
		return;
	Dest = TeleportTarget + vect(0,0,1) * (Pawn.CollisionHeight + 4);
	if ( Pawn.SetLocation(Dest) )
	{
		Log("VR teleport to "$Dest, 'UT2004VR');
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		Pawn.SetPhysics(PHYS_Falling);
		// the head lands over the target
		Anchor = HeadPos;
		Anchor.Z = 0;
		BlinkUntil = Level.TimeSeconds + 0.12;
	}
}

// debug: die now (UT's suicide command does nothing here), e.g. to test respawn in a TestExec sequence
exec function VRDie()
{
	bMenuBeforeRespawn = false;   // else the first fire opens UT's menu (and pauses) instead of respawning
	if ( Pawn != None )
		Pawn.Died(self, class'DamageType', Pawn.Location);
}

exec function VRRespawn()
{
	bFrozen = false;
	ServerReStartPlayer();
}

// other gametypes (Instant Action, via VRMutator) bring their own HUD: VRHUD draws the desktop mirror and the menu
// backdrop the headset panel needs (the VR HUD itself is drawn into the eyes by this controller)
simulated function ClientSetHUD(class<HUD> newHUDClass, class<Scoreboard> newScoringClass)
{
	local class<HUD> Orig;

	if ( newHUDClass != None && ClassIsChildOf(newHUDClass, class'HudCDeathMatch') && newHUDClass != class'VRHUD' )
	{
		Log("UT2004VR: HUD "$newHUDClass$" -> VRHUD", 'UT2004VR');
		Orig = newHUDClass;
		newHUDClass = class'VRHUD';
	}
	Super.ClientSetHUD(newHUDClass, newScoringClass);
	// the game type's own HUD keeps running beside it: its screen part goes into the headset (VRHUD.Shadow)
	if ( Orig != None && VRHUD(myHUD) != None && bVROriginalHud )
		VRHUD(myHUD).SetShadow(Orig);
}

// as CinematicPlayer does on fire: open the main menu and leave the intro
function SkipCinematic()
{
	Log("UT2004VR: skipping the cinematic", 'UT2004VR');
	if ( Player != None && Player.GUIController != None )
		Player.GUIController.OpenMenu(class'GameEngine'.default.MainMenuClass);
	ConsoleCommand("DISCONNECT");
}

// spectating: fire (mouse button, or the trigger in controller mode) looks through the next player's eyes,
// alt-fire goes back to your own camera. Read from the buttons: the Fire/AltFire execs never got here while
// spectating (clicking did nothing), and VRWeaponInput doesn't map the trigger without a pawn.
function SpectatorButtons()
{
	local bool bF, bA;
	bF = bFire != 0 || (!bKeyboardMouse && bBtnFire);
	bA = bAltFire != 0 || (!bKeyboardMouse && bBtnAlt);
	// the buttons are followed in every state, but only act while spectating or waiting: a click that skipped
	// Assault's intro (which then puts you in PlayerWaiting) was still held and counted as a new press there
	if ( IsInState('Spectating') || IsInState('PlayerWaiting') )
	{
		if ( bF && !bSpecFireHeld )
			SpectatorFire();
		if ( bA && !bSpecAltHeld )
			SpectatorAltFire();
	}
	bSpecFireHeld = bF;
	bSpecAltHeld = bA;
}

function SpectatorFire()
{
	if ( Level.TimeSeconds - SpecSwitchTime < 0.3 && Level.TimeSeconds >= SpecSwitchTime )
		return;   // the exec and the button both saw the same click
	SpecSwitchTime = Level.TimeSeconds;
	// a Matinee intro (the trigger in controller mode comes this way): fire only ends it, as above
	if ( bViewingMatineeCinematic && Level.NetMode == NM_Standalone )
	{
		Log("UT2004VR: fire in the intro: skipping it", 'UT2004VR');
		Level.Game.SceneAbort();
		return;
	}
	// waiting for the match ("Press FIRE to start!"): ready (UT's PlayerWaiting.Fire)
	if ( IsInState('PlayerWaiting') )
	{
		if ( Level.TimeSeconds > 0.2 )
			ServerReStartPlayer();
		Log("UT2004VR: fire while waiting: ready "$(PlayerReplicationInfo != None && PlayerReplicationInfo.bReadyToPlay), 'UT2004VR');
		return;
	}
	if ( bFrozen )
	{
		if ( TimerRate <= 0.0 || TimerRate > 1.0 )
			bFrozen = false;
		return;
	}
	ServerViewNextPlayer();
	Log("UT2004VR: spectating "$ViewTarget, 'UT2004VR');
}

function SpectatorAltFire()
{
	if ( IsInState('PlayerWaiting') )
	{
		SpectatorFire();
		return;
	}
	if ( Level.TimeSeconds - SpecSwitchTime < 0.3 && Level.TimeSeconds >= SpecSwitchTime )
		return;
	SpecSwitchTime = Level.TimeSeconds;
	bBehindView = false;
	ServerViewSelf();
	Log("UT2004VR: spectating own camera", 'UT2004VR');
}

// debug: press fire for a moment (TestExec can't hold a button)
exec function VRTapFire()
{
	bFire = 1;
	TapFireUntil = Level.TimeSeconds + 0.2;
	Fire(0);   // a click is both: the alias "Button bFire | Fire"
}

// (these global versions win over PlayerController's state Spectating ones, so spectating is handled here too:
// fire = the next player, alt-fire = back to your own camera, as UT's Spectating.Fire/AltFire do)
exec function Fire(optional float F)
{
	// the startup intro (CinematicGame): to the main menu; a Matinee intro in a game (Assault's briefing): UT's own
	// Fire aborts the scene
	if ( IsCinematic() && CinematicGame(Level.Game) != None )
	{
		SkipCinematic();
		return;
	}
	// a Matinee intro (Assault's briefing): the click only ends it, as UT's Fire does. Assault then puts you in
	// PlayerWaiting in the same moment, and the button watching (later this tick) would take the held button as
	// a new press there and make you ready: the click is used up
	if ( bViewingMatineeCinematic && Level.NetMode == NM_Standalone )
	{
		Log("UT2004VR: fire in the intro: skipping it", 'UT2004VR');
		SpecSwitchTime = Level.TimeSeconds;
		bSpecFireHeld = true;
		Level.Game.SceneAbort();
		return;
	}
	if ( IsInState('Spectating') )
	{
		SpectatorFire();
		return;
	}
	// "Press FIRE to start!": what UT's PlayerWaiting.Fire does (this global version wins over it)
	if ( IsInState('PlayerWaiting') )
	{
		SpectatorFire();
		return;
	}
	Super.Fire(F);
}

exec function AltFire(optional float F)
{
	if ( IsCinematic() && CinematicGame(Level.Game) != None )
	{
		SkipCinematic();
		return;
	}
	if ( IsInState('Spectating') )
	{
		SpectatorAltFire();
		return;
	}
	if ( IsInState('PlayerWaiting') )
	{
		Fire(F);
		return;
	}
	Super.AltFire(F);
}

function PawnDied(Pawn P)
{
	Log("UT2004VR: died", 'UT2004VR');
	Super.PawnDied(P);
}

function ClientRestart(Pawn NewPawn)
{
	Super.ClientRestart(NewPawn);
	Log("UT2004VR: restart (spawned) - height re-measured, chair kept="$bChairMeasured, 'UT2004VR');
	if ( bKeyboardMouse )
		SanitizeAim();
	bNeedSpawnFacing = true;
	bNeedHeight = true;
	// average the height over ~1.5 s again (WornTime is already past the 2 s gate: it took one sample)
	WornTime = FMin(WornTime, 0.5);
	CalibSum = 0;
	CalibCount = 0;
	CalibFwdSum = vect(0,0,0);
	ChairCount = 0;
	bAnchorValid = false;
}

function FaceOpenSpace()
{
	local int i, BestYaw;
	local float Best, D;
	local vector Dir, HitLoc, HitNorm, Start;
	local rotator R;

	Start = VRHeadWorld;
	Best = -1;
	for ( i = 0; i < 16; i++ )
	{
		R.Yaw = i * 4096;
		Dir = vector(R);
		if ( Trace(HitLoc, HitNorm, Start + Dir * 4000, Start, false) != None )
			D = VSize(HitLoc - Start);
		else
			D = 4000;
		if ( D > Best )
		{
			Best = D;
			BestYaw = R.Yaw;
		}
	}
	// make the head's current facing point at BestYaw
	R = rotator(HeadF);
	PlayYaw = BestYaw - R.Yaw;
	bBodyYawValid = false;
}

function VRPlayerMove(float DeltaTime)
{
	local vector X, Y, Z, NewAccel, HD, HandLoc;
	local rotator R;
	local float Mag;
	local bool bJumpNow;
	local EDoubleClickDir DodgeNow;
	local bool bCrouchNow;
	local int Diff;
	local float SteerDeg;
	local eDoubleClickDir Dodge;

	UpdateHeadWorld();
	if ( bNeedSpawnFacing )
	{
		bNeedSpawnFacing = false;
		FaceOpenSpace();
		UpdateHeadWorld();
	}
	VRTurn(DeltaTime);
	VRFollowHead();
	UpdateHeadWorld();

	// movement basis: the body heading (turning toward the gaze while moving forward), the head, or the left hand
	R = VRHeadRot;
	if ( !bBodyYawValid )
	{
		BodyYaw = VRHeadRot.Yaw;
		bBodyYawValid = true;
	}
	if ( bSteerByGaze )
	{
		if ( !bChairYawValid )
		{
			ChairYaw = rotator(HeadF).Yaw;
		ChairPitch = rotator(HeadF).Pitch;
			bChairYawValid = true;
		}
		// any stick movement (forward, back or strafe), always toward the gaze
		if ( Sqrt(StickMX * StickMX + StickMY * StickMY) > 0.15 )
		{
			// look angle relative to the chair, in degrees
			Diff = (rotator(HeadF).Yaw - ChairYaw) & 65535;
			if ( Diff > 32768 )
				Diff -= 65536;
			SteerDeg = float(Diff) * 360.0 / 65536.0;
			if ( Abs(SteerDeg) > SteerDeadzone )
			{
				if ( SteerDeg > 0 )
					SteerDeg -= SteerDeadzone;
				else
					SteerDeg += SteerDeadzone;
				SteerDeg = FClamp(SteerDeg * SteerGain, -SteerMaxDegPerSec, SteerMaxDegPerSec) * FMin(1.0, Sqrt(StickMX * StickMX + StickMY * StickMY));
				PlayYaw += int(SteerDeg * DeltaTime * 65536.0 / 360.0);
				UpdateHeadWorld();
			}
		}
		// walking (and the body) go along the chair's forward in the game world
		BodyYaw = PlayYaw + ChairYaw;
		R.Yaw = BodyYaw;
	}
	else if ( bGazeHeading )
	{
		if ( StickMY > 0.15 )
		{
			// angular speed proportional to the angle between heading and gaze (and to the forward push)
			Diff = (VRHeadRot.Yaw - BodyYaw) & 65535;
			if ( Diff > 32768 )
				Diff -= 65536;
			if ( Abs(Diff) < 64 )
				BodyYaw = VRHeadRot.Yaw;   // the last fraction of a degree (integer steps would stall it)
			else
				BodyYaw += int(float(Diff) * FMin(1.0, HeadingTurnRate * StickMY * DeltaTime));
		}
		R.Yaw = BodyYaw;
	}
	else if ( bHandRelativeMove && bHandOK[0] != 0 )
	{
		GetHandWorld(0, HandLoc, HD);
		R = rotator(HD);
	}
	R.Pitch = 0;
	R.Roll = 0;
	GetAxes(R, X, Y, Z);

	Mag = FMin(1.0, Sqrt(StickMX * StickMX + StickMY * StickMY));
	if ( Mag < 0.15 )
	{
		Mag = 0;
		NewAccel = vect(0,0,0);
	}
	else
		NewAccel = Normal(StickMY * X + StickMX * Y) * Pawn.AccelRate;
	Pawn.GroundSpeed = Pawn.Default.GroundSpeed * MoveSpeedScale * FMax(Mag, 0.3);
	VRMoveAmount = Mag;

	// teleport: push the right stick forward to aim, release to go
	if ( bTeleport && StickTY > 0.6 && Abs(StickTX) < 0.6 )
	{
		bAiming = true;
		VRTeleportAim();
	}
	else if ( bAiming && StickTY < 0.3 )
	{
		bAiming = false;
		ShowArc(0);
		VRTeleportGo();
	}

	// jump: left stick click, only with the stick near centre (pushing the stick hard can click it by accident)
	bJumpNow = bBtnJump && !bOldJump;
	if ( bJumpNow && Mag >= 0.5 )
	{
		Log("UT2004VR: jump click ignored (stick pushed "$Mag$")", 'UT2004VR');
		bJumpNow = false;
	}
	bOldJump = bBtnJump;
	// dodge: left trigger, toward where the left stick points (UT's double-tap dodge)
	DodgeNow = DCLICK_None;
	if ( bBtnDodge && !bOldDodge )
	{
		DodgeNow = StickDodgeDir();
		Log("UT2004VR: dodge "$GetEnum(enum'EDoubleClickDir', DodgeNow)$" crouched="$Pawn.bIsCrouched, 'UT2004VR');
	}
	bOldDodge = bBtnDodge;
	// jumping or dodging stands you up (UT can do neither while crouched); crouch (left grip) stays off until released
	if ( Pawn.bIsCrouched && (bJumpNow || DodgeNow != DCLICK_None) )
	{
		bCrouchSuppressed = true;
		Pawn.ShouldCrouch(false);
		// UT refuses both while bIsCrouched is still set: replay the move once the pawn has stood up
		if ( bJumpNow )
			PendingStandMove = 1;
		else
		{
			PendingStandMove = 2;
			PendingDodge = DodgeNow;
		}
		PendingStandUntil = Level.TimeSeconds + 0.3;
		bJumpNow = false;
		DodgeNow = DCLICK_None;
	}
	if ( bJumpNow )
	{
		Log("UT2004VR: jump", 'UT2004VR');
		bPressedJump = true;
	}
	if ( !bBtnCrouch )
		bCrouchSuppressed = false;
	bOldCrouch = bBtnCrouch;
	bCrouchNow = (bBtnCrouch && !bCrouchSuppressed) || HeadPos.Z < CrouchHeadMeters;
	if ( bCrouchNow )
		bDuck = 1;
	else
		bDuck = 0;

	// the pawn faces where the head faces; the controller (aim) follows the gun when there is one
	R = VRHeadRot;
	R.Roll = 0;
	if ( GunActive() )
		SetRotation(GunRot());
	else
		SetRotation(R);
	R.Pitch = 0;
	if ( bGazeHeading || bSteerByGaze )
		R.Yaw = BodyYaw;     // the body (and UT's dodge directions) follow the heading, not the head
	Pawn.SetRotation(R);
	Pawn.SetViewPitch(VRHeadRot.Pitch);

	if ( bCalib )
		UpdateCalib();
	if ( bCalibGun )
	{
		LogNewEffects();
		if ( Pawn.Physics == PHYS_Falling )
			Log("VR air: z="$Pawn.Location.Z$" vz="$Pawn.Velocity.Z$" dbl="$bDoubleJump$" jumps left="$xPawn(Pawn).MultiJumpRemaining, 'UT2004VR');
	}
	if ( bDebugLog && Level.TimeSeconds > NextDebugLog )
	{
		NextDebugLog = Level.TimeSeconds + 1.0;
		if ( bGunCalibrated && Pawn.Weapon != None )
			LogGunError(Pawn.Weapon);
		Log("VR seq="$HeadSeq$" pawn="$Pawn.Location$" phys="$GetEnum(enum'EPhysics', Pawn.Physics)$" playyaw="$(PlayYaw & 65535)$" head="$VRHeadWorld$" stick="$StickMX$","$StickMY$"/"$StickTX$","$StickTY$" aiming="$bAiming$" tpvalid="$bTeleportValid$" duck="$bDuck$" headyaw="$(VRHeadRot.Yaw & 65535)$" bodyyaw="$(BodyYaw & 65535)$" vel="$Pawn.Velocity, 'UT2004VR');
	}
	VRWeaponInput();
	UpdateGun();
	Dodge = DCLICK_None;
	if ( PendingStandMove != 0 )
	{
		if ( Level.TimeSeconds > PendingStandUntil )
			PendingStandMove = 0;
		else if ( !Pawn.bIsCrouched )
		{
			if ( PendingStandMove == 1 )
				bPressedJump = true;
			else
				Dodge = PendingDodge;
			PendingStandMove = 0;
		}
	}
	else
		Dodge = DodgeNow;
	// UT scales the dodge by GroundSpeed, which VR walking lowers for comfort: dodge at full stock speed
	if ( Dodge != DCLICK_None )
		Pawn.GroundSpeed = Pawn.Default.GroundSpeed;
	ProcessMove(DeltaTime, NewAccel, Dodge, rot(0,0,0));
	bPressedJump = false;
	// xPawn.DoJump sets bDoubleJump for a mid-air jump; UT's own PlayerMove clears it every frame. Left set,
	// ProcessMove fires DoDoubleJump (Velocity.Z = 365, no jump used up for a local player) every tick:
	// an endless thrust that pinned the player to the ceiling.
	bDoubleJump = false;
}

// keyboard/mouse aim rotation without roll, pitch within +-88 deg. UT's UpdateRotation can carry a view roll
// (tied to the pawn's desired roll), and controller-mode play leaves the hand's roll/pitch in Rotation; either
// tilts the view and turns the body-fixed gun over.
simulated function rotator CleanAim(rotator R)
{
	local int P;
	P = R.Pitch & 65535;
	if ( P > 32768 )
		P -= 65536;
	R.Pitch = Clamp(P, -16000, 16000);
	R.Roll = 0;
	return R;
}

// debug: how far (deg) the gun's barrel points above (+) the view centre
function float GunVsViewPitch()
{
	local vector G, V;
	G = vector(CleanAim(Rotation));
	V = vector(VRHeadRot);
	return (Atan(G.Z, Sqrt(G.X * G.X + G.Y * G.Y)) - Atan(V.Z, Sqrt(V.X * V.X + V.Y * V.Y))) * 180.0 / 3.14159265;
}

// debug: how far (deg) the gun's barrel points right (+) of the view centre
function float GunVsViewYaw()
{
	local int D;
	D = (CleanAim(Rotation).Yaw - VRHeadRot.Yaw) & 65535;
	if ( D > 32768 )
		D -= 65536;
	return D * 360.0 / 65536.0;
}

function SanitizeAim()
{
	local rotator R;
	R = CleanAim(Rotation);
	if ( R != Rotation )
		SetRotation(R);
}

// keyboard/mouse mode: UT's own walking (WASD, double-tap dodge, jump, crouch, mouse turn/aim through
// UpdateRotation); the headset only looks around on top of the mouse heading
function KBMPlayerMove(float DeltaTime)
{
	// debug: VRStick strafes / walks as the keys would (aStrafe / aForward, read by PlayerWalking after this)
	if ( Level.TimeSeconds < DebugStickUntil )
	{
		aStrafe = DebugStickX * 6000;
		aForward = DebugStickY * 6000;
	}
	if ( !bAnchorValid )
	{
		Anchor = HeadPos;
		Anchor.Z = 0;
		bAnchorValid = true;
	}
	// until the chair forward is measured: the current gaze, but only a level one (a downward glance at the
	// keyboard gives a meaningless heading; then wait)
	if ( !bChairYawValid && Abs(Normal(HeadF).Z) < 0.17 && VSize(HeadF) > 0.5 )
	{
		ChairYaw = rotator(HeadF).Yaw;
		ChairPitch = rotator(HeadF).Pitch;
		bChairYawValid = true;
	}
	Pawn.GroundSpeed = Pawn.Default.GroundSpeed;   // VR walking lowers it; flat-UT speed here
	SanitizeAim();
	ShowArc(0);
	bAiming = false;
}

function KBMAfterMove()
{
	if ( bDebugLog && Rotation.Pitch != LastLoggedPitch && Level.TimeSeconds < PitchLogUntil )
	{
		Log("VR pitch change "$LastLoggedPitch$" -> "$Rotation.Pitch$" phys "$GetEnum(enum'EPhysics', Pawn.Physics)$" vz "$Pawn.Velocity.Z$" t "$Level.TimeSeconds, 'UT2004VR');
		LastLoggedPitch = Rotation.Pitch;
	}
	SanitizeAim();
	if ( bDebugLog && Level.TimeSeconds > NextDebugLog )
	{
		NextDebugLog = Level.TimeSeconds + 1.0;
		Log("VR kbm pitch: gun-vs-view "$(GunVsViewPitch())$" deg, yaw "$GunVsViewYaw()$" deg, aim "$Rotation$" view "$VRHeadRot$" chair "$ChairYaw$"/"$ChairPitch$" behind "$bBehindView$" state "$GetStateName()$" gun "$GunModel, 'UT2004VR');
		if ( GunModel != None )
			Log("VR kbm gun rot "$GunModel.Rotation, 'UT2004VR');
		Log("VR kbm: aim="$Rotation$" chair="$ChairYaw$" playyaw="$PlayYaw$" head="$HeadPos$" headrot="$VRHeadRot$" gun="$GunModel$" cal="$bGunCalibrated$" paused="$(Level.Pauser != None), 'UT2004VR');
	}
	// the playspace follows the mouse heading: looking straight ahead (the chair's forward) = where you walk
	PlayYaw = Rotation.Yaw - ChairYaw;
	BodyYaw = Rotation.Yaw;
	UpdateHeadWorld();
	UpdateGun();
}

// the frame your view rides in: the vehicle. On a gunner seat or turret UT turns the seat itself with the mouse,
// so the view follows the vehicle under it instead (or, on a stationary turret, your heading when you got on):
// the mouse turns the gun, never the view.
simulated function rotator VehicleFrame()
{
	local rotator R;
	if ( ONSWeaponPawn(Pawn) != None )
	{
		if ( ONSWeaponPawn(Pawn).VehicleBase != None )
			return ONSWeaponPawn(Pawn).VehicleBase.Rotation;
		R.Yaw = TurretEntryYaw;
		return R;
	}
	// Assault turrets turn toward your gaze (SteerASTurret): a frame turning with them would lead them on forever
	if ( ASTurret(Pawn) != None )
	{
		if ( ASTurret(Pawn).TurretBase != None )
			R.Yaw = ASTurret(Pawn).TurretBase.Rotation.Yaw;
		else
			R.Yaw = TurretEntryYaw;
		return R;
	}
	return Pawn.Rotation;
}

// The view's heading in a vehicle. Vehicles that turn toward the view (Manta, Raptor: bFollowLookDir) turn toward
// your gaze; if the view were locked to them, a look to the side would lead them forever (they spun). So the view
// only follows them at GazeSteerFollow: a glance turns the vehicle to face it and it stops; your view turns slowly.
// behind view in a vehicle: UT's own chase distances (TPCamLookat, TPCamDistance), but along the vehicle's heading
// (not the mouse or your head) and a little from above; stops at walls
simulated function vector VehicleChaseCam(Vehicle V, int Yaw)
{
	local rotator R, YawR;
	local vector LookAt, Cam, HitL, HitN;
	YawR.Yaw = Yaw;
	R.Yaw = Yaw;
	R.Pitch = int(-VehicleBehindPitch * 65536.0 / 360.0);
	LookAt = V.GetCameraLocationStart() + (V.TPCamLookat >> YawR) + V.TPCamWorldOffset;
	Cam = LookAt + ((vect(-1,0,0) * V.TPCamDistance * VehicleBehindScale) >> R);
	if ( Trace(HitL, HitN, Cam, LookAt, false, vect(20,20,20)) != None )
		Cam = HitL;
	return Cam;
}

simulated function int VehicleViewYaw()
{
	local int D;
	local float DT;
	if ( !Vehicle(Pawn).bFollowLookDir || ONSWeaponPawn(Pawn) != None )
		return VehicleFrame().Yaw;
	DT = FClamp(Level.TimeSeconds - LastViewYawT, 0, 0.1);
	LastViewYawT = Level.TimeSeconds;
	D = (Pawn.Rotation.Yaw - int(VehViewYaw)) & 65535;
	if ( D > 32768 )
		D -= 65536;
	VehViewYaw += D * FMin(1, GazeSteerFollow * DT);
	return int(VehViewYaw);
}

state PlayerTurreting
{
	function PlayerMove(float DeltaTime)
	{
		// the seat would turn with the mouse: not in VR (the gun aims where you look)
		if ( VRActive() )
		{
			aTurn = 0;
			aLookUp = 0;
			if ( Level.TimeSeconds < DebugTurnUntil )
				aTurn = DebugTurn;
		}
		// Assault's turrets turn only from this input (their own Rotation is the aim): steer them toward the gaze
		if ( VRActive() && ASTurret(Pawn) != None )
			SteerASTurret(ASTurret(Pawn), DeltaTime);
		Super.PlayerMove(DeltaTime);
		if ( VRActive() && Vehicle(Pawn) != None && ASTurret(Pawn) == None )
			GazeVehicleRotation();
	}
}

// the yaw / pitch input that turns an Assault turret toward what you look at (traced from the head, so the shot
// lands there despite the gun's offset), closing the gap over ASTurretFollow seconds through its own inertia
function SteerASTurret(ASTurret T, float DeltaTime)
{
	local vector HitL, HitN, End;
	local rotator Want, Err;
	local float K;

	if ( DeltaTime <= 0 || T.RotationSpeed <= 0 )
		return;
	End = VRHeadWorld + vector(VRHeadRot) * 20000;
	if ( T.Trace(HitL, HitN, End, VRHeadWorld, true) == None )
		HitL = End;
	Want = rotator(HitL - T.GetFireStart());
	Err = Normalize(Want - T.Rotation);
	K = FMin(1, DeltaTime / FMax(ASTurretFollow, 0.01));
	// UpdateRocketAcceleration: Accel = Inertia * Accel + dt * RotationSpeed * Change, then Rotation += Accel
	aTurn = (Err.Yaw * K - T.RotationInertia * T.YawAccel) / (DeltaTime * T.RotationSpeed);
	aLookUp = (Err.Pitch * K - T.RotationInertia * T.PitchAccel) / (DeltaTime * T.RotationSpeed);
}

// debug: turn as the mouse would, aTurn units for 2 s (turrets: PlayerTurreting reads aTurn)
exec function VRMouseTurn(float A)
{
	DebugTurn = A;
	DebugTurnUntil = Level.TimeSeconds + 2;
}

// a guided Redeemer warhead (or any pawn flown in UT's PlayerRocketing state) is your pawn
simulated function bool IsRiding()
{
	return Pawn != None && Vehicle(Pawn) == None && IsInState('PlayerRocketing');
}

state PlayerRocketing
{
	function PlayerMove(float DeltaTime)
	{
		if ( VRActive() && Pawn != None )
		{
			UpdateLaser(false, vect(0,0,0), vect(1,0,0));
			if ( GunModel != None )
				GunModel.bHidden = true;
			// controller mode: the right stick steers (UT reads the mouse's aTurn/aLookUp), the trigger detonates
			if ( !bKeyboardMouse )
			{
				if ( Level.TimeSeconds < DebugStickUntil )
				{
					StickTX = DebugStickX;
					StickTY = DebugStickY;
				}
				aTurn += StickTX * RedeemerSteer;
				aLookUp += StickTY * RedeemerSteer;
				if ( bDebugLog && (StickTX != 0 || StickTY != 0) && Level.TimeSeconds > NextCrossLog )
				{
					NextCrossLog = Level.TimeSeconds + 0.5;
					Log("UT2004VR: warhead steer stick "$StickTX$","$StickTY$" -> aTurn "$aTurn$" aLookUp "$aLookUp, 'UT2004VR');
				}
				if ( bBtnFire && !bOldFire )
					Fire(0);
				bOldFire = bBtnFire;
			}
		}
		Super.PlayerMove(DeltaTime);
	}
}

state PlayerWalking
{
	function PlayerMove(float DeltaTime)
	{
		if ( VRActive() && Pawn != None && bKeyboardMouse )
		{
			KBMPlayerMove(DeltaTime);
			Super.PlayerMove(DeltaTime);
			KBMAfterMove();
		}
		else if ( VRActive() && Pawn != None )
			VRPlayerMove(DeltaTime);
		else
			Super.PlayerMove(DeltaTime);
	}
}

// in VR the mouse only turns the playspace (handy at the desk without controllers)
function UpdateRotation(float DeltaTime, float maxPitch)
{
	if ( VRActive() && Vehicle(Pawn) != None )
	{
		GazeVehicleRotation();
		return;
	}
	if ( !VRActive() || bKeyboardMouse )
	{
		Super.UpdateRotation(DeltaTime, maxPitch);
		return;
	}
	PlayYaw += int(32.0 * DeltaTime * aTurn);
	BodyYaw += int(32.0 * DeltaTime * aTurn);
}

exec function VRStatus()
{
	ClientMessage("UT2004VR active="$VRActive()$" packets="$Link.Packets$" seq="$HeadSeq$" head="$HeadPos$" fov="$EyeFOV$" eye="$EyeW$"x"$EyeH);
}

function UpdateCalib()
{
	local int i;
	local rotator R;
	local vector Dir;
	local int Yaws[5], Pitches[5];

	Yaws[0] = 0;     Pitches[0] = 0;
	Yaws[1] = 30;    Pitches[1] = 0;
	Yaws[2] = 0;     Pitches[2] = 30;
	Yaws[3] = 30;    Pitches[3] = 25;
	Yaws[4] = -40;   Pitches[4] = -25;
	// fixed in the world, laid out around where the head looked when calibration started
	if ( CalibDots[0] == None )
	{
		// does OrthoRotation(F, U^F, U) give back the head's axes (pitch and roll included)?
		Log("UT2004VR calib: HeadF="$HeadF$" HeadU="$HeadU$" rot="$FrameRot(HeadF, HeadU)$" back F="$vector(FrameRot(HeadF, HeadU))$" back U="$(vect(0,0,1) >> FrameRot(HeadF, HeadU)), 'UT2004VR');
		CalibOrigin = VRHeadWorld;
		CalibRot = VRHeadRot;
		CalibRot.Roll = 0;
		CalibRot.Pitch = 0;
	}
	for ( i = 0; i < 5; i++ )
	{
		R = CalibRot;
		R.Yaw += Yaws[i] * 65536 / 360;
		R.Pitch += Pitches[i] * 65536 / 360;
		Dir = vector(R);
		CalibPts[i] = CalibOrigin + Dir * 300;
		if ( CalibDots[i] == None )
			CalibDots[i] = Spawn(class'VRArcDot', self,, CalibPts[i]);
		if ( CalibDots[i] != None )
		{
			CalibDots[i].SetLocation(CalibPts[i]);
			CalibDots[i].bHidden = false;
			CalibDots[i].Texture = Texture'Engine.WhiteSquareTexture';
			CalibDots[i].Style = STY_Normal;
			CalibDots[i].SetDrawScale(1.5);
		}
	}
}

// ---------------------------------------------------------------------------
// Eye render targets
// ---------------------------------------------------------------------------
function UpdateEyeTextures()
{
	local int i;

	if ( EyeW < 256 || EyeW > 4096 || EyeH < 256 || EyeH > 4096 )
		return;
	for ( i = 0; i < 2; i++ )
	{
		if ( EyeTex[i] == None )
		{
			EyeTex[i] = ScriptedTexture(Level.ObjectPool.AllocateObject(class'ScriptedTexture'));
			EyeTex[i].Client = self;
		}
		if ( EyeTexW != EyeW || EyeTexH != EyeH )
			EyeTex[i].SetSize(EyeW, EyeH);
		// (the revision is bumped by VRMirrorInteraction right before it triggers the render)
	}
	if ( EyeTexW != EyeW || EyeTexH != EyeH )
		Log("UT2004VR: eye render targets "$EyeW$"x"$EyeH$" fov "$EyeFOV, 'UT2004VR');
	// the last interaction of the frame renders the eyes (index 0 = PostRender'ed last)
	if ( MirrorIA == None && Player != None && Player.InteractionMaster != None )
	{
		// interactions outlive the level: reuse the one an earlier game's controller added
		for ( i = 0; i < Player.LocalInteractions.Length; i++ )
			if ( VRMirrorInteraction(Player.LocalInteractions[i]) != None )
				MirrorIA = VRMirrorInteraction(Player.LocalInteractions[i]);
		if ( MirrorIA == None )
			MirrorIA = VRMirrorInteraction(Player.InteractionMaster.AddInteraction("UT2004VR.VRMirrorInteraction", Player));
		if ( MirrorIA != None )
		{
			MirrorIA.PC = self;
			for ( i = 0; i < Player.LocalInteractions.Length; i++ )
				if ( Player.LocalInteractions[i] == MirrorIA )
				{
					Player.LocalInteractions.Remove(i, 1);
					break;
				}
			Player.LocalInteractions.Insert(0, 1);
			Player.LocalInteractions[0] = MirrorIA;
			Log("UT2004VR: mirror interaction added ("$Player.LocalInteractions.Length$" local, "$Player.InteractionMaster.GlobalInteractions.Length$" global)", 'UT2004VR');
		}
	}
	EyeTexW = EyeW;
	EyeTexH = EyeH;
}

simulated event RenderTexture(ScriptedTexture Tex)
{
	local int Eye, i;
	local vector Loc;
	local rotator Rot;
	local color EyeTag;
	local SpinnyWeap Spinny;
	local float A;

	if ( Tex == ScopeTex && ScopeTex != None )
	{
		RenderScope(Tex);
		return;
	}
	if ( Tex == EyeTex[1] )
		Eye = 1;
	else if ( Tex != EyeTex[0] )
		return;
	UpdateHeadWorld();
	// Physics moves the pawn after PlayerMove placed the gun, so re-place it now, right before the eyes render
	// (otherwise it lags one frame behind the camera and slides sideways while strafing)
	if ( Eye == 0 && Pawn != None && GunActive() )
	{
		UpdateGun();
		MeasureBeamGap();
	}
	GetEyeView(Eye, Loc, Rot);
	if ( bCalibGun && Eye == 0 && GunModel != None && Level.TimeSeconds > NextGunEyeLog )
	{
		NextGunEyeLog = Level.TimeSeconds + 0.5;
		Log("VR gun-in-eye: "$((GunModel.Location - Loc) << Rot)$" vel="$Pawn.Velocity$" headrot="$VRHeadRot$" aim="$Rotation, 'UT2004VR');
	}
	ScopeHidden.Length = 0;
	// the menus' 3D previews (Settings > Player's character, Weapons' gun, the model picker): UT spawns them in the
	// world just in front of the camera and draws them into the menu; in the eyes they hung at your face and
	// turned with your head. Hidden only for the eye renders: the menu panel still shows them.
	foreach DynamicActors(class'SpinnyWeap', Spinny)
		ScopeHide(Spinny);
	// dead (no pawn): keep the eyes rendering from where you fell, so the headset image never freezes
	if ( Pawn != None )
	{
		// in a vehicle or on a turret your own character sits at your eyes (UT draws the driver on gunner seats
		// and turrets): not in your view; others still see it
		if ( Vehicle(Pawn) != None && Vehicle(Pawn).Driver != None && !bBehindView )
		{
			ScopeHide(Vehicle(Pawn).Driver);
			ScopeHideAttached(Vehicle(Pawn).Driver);
			if ( Vehicle(Pawn).Driver.Weapon != None )
				ScopeHide(Vehicle(Pawn).Driver.Weapon.ThirdPersonActor);
		}
		Tex.DrawPortal(0, 0, Tex.USize, Tex.VSize, Pawn, Loc, Rot, EyeFOV, true);
	}
	else if ( IsFreeView() && bCineCam )
	{
		// the portal renders from its camera actor's zone: a marker at the cinematic camera
		if ( CineCam == None )
			CineCam = Spawn(class'VRCineCam');
		if ( CineCam != None )
		{
			CineCam.SetLocation(Loc);
			Tex.DrawPortal(0, 0, Tex.USize, Tex.VSize, CineCam, Loc, Rot, EyeFOV, true);
		}
	}
	else
		Tex.DrawPortal(0, 0, Tex.USize, Tex.VSize, self, Loc, Rot, EyeFOV, true);
	for ( i = 0; i < ScopeHidden.Length; i++ )
		if ( ScopeHidden[i] != None )
			ScopeHidden[i].bHidden = false;
	ScopeHidden.Length = 0;

	if ( bRedeemerWindow && IsRiding() )
		DrawRedeemerWindow(Tex, Loc, Rot);
	if ( bCalib )
		DrawCalibTex(Tex, Loc, Rot);
	if ( bCalibGun )
		DrawGunMarks(Tex, Loc, Rot);
	if ( bVRHud )
		DrawVRHud(Tex, Loc, Rot);
	if ( bVignette && VRMoveAmount > 0 )
	{
		A = FClamp(VRMoveAmount, 0, 1) * 150;
		EyeTag.R = 0; EyeTag.G = 0; EyeTag.B = 0; EyeTag.A = byte(A);
		Tex.DrawTile(0, 0, Tex.USize, Tex.VSize, 0, 0, 256, 256, Texture'VRVignette', EyeTag);
	}
	if ( Level.TimeSeconds < BlinkUntil )
	{
		EyeTag.R = 0; EyeTag.G = 0; EyeTag.B = 0; EyeTag.A = 255;
		Tex.DrawTile(0, 0, Tex.USize, Tex.VSize, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', EyeTag);
	}
	// eye tag for the d3d9 proxy (red = left, blue = right); outside every headset's crop
	EyeTag.A = 255; EyeTag.G = 0;
	if ( Eye == 0 ) { EyeTag.R = 255; EyeTag.B = 0; }
	else { EyeTag.R = 0; EyeTag.B = 255; }
	Tex.DrawTile(0, 0, 6, 6, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', EyeTag);
}

function MarkAt(ScriptedTexture Tex, vector P, vector Loc, rotator Rot, color Col, int Sz)
{
	local vector L;
	local float h, px, py;
	h = Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
	L = (P - Loc) << Rot;
	if ( L.X <= 1 )
		return;
	px = Tex.USize * 0.5 * (1 + (L.Y / L.X) / h);
	py = Tex.VSize * 0.5 - Tex.USize * 0.5 * (L.Z / L.X) / h;
	Tex.DrawTile(px - Sz / 2, py - Sz / 2, Sz, Sz, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Col);
}

// white: muzzle bone; yellow: points behind it along the mesh X axis; red: along the tip bone's X axis
function DrawGunMarks(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local coords C;
	local color Wh, Ye, Re;
	local int i;

	if ( Pawn == None || GunModel == None || !bGunCalibrated )
		return;
	C = GunModel.GetBoneCoords('tip');
	Wh.R = 255; Wh.G = 255; Wh.B = 255; Wh.A = 255;
	Ye.R = 255; Ye.G = 230; Ye.B = 0; Ye.A = 255;
	Re.R = 255; Re.G = 0; Re.B = 0; Re.A = 255;
	MarkAt(Tex, C.Origin, Loc, Rot, Wh, 14);
	for ( i = 1; i <= 4; i++ )
	{
		MarkAt(Tex, C.Origin - vector(Rotation) * (i * 8), Loc, Rot, Ye, 10);
		MarkAt(Tex, C.Origin - C.XAxis * (i * 8), Loc, Rot, Re, 10);
	}
}

// ---------------------------------------------------------------------------
// VR HUD: each item sits at a 3D point in front of the head (HudDistance) and is projected into each eye,
// so it has real stereo depth instead of the "infinitely far" look of a flat overlay
// ---------------------------------------------------------------------------
function bool HudProject(ScriptedTexture Tex, vector P, vector Loc, rotator Rot, out float PX, out float PY)
{
	local vector L;
	local float h;
	h = Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
	L = (P - Loc) << Rot;
	if ( L.X <= 1 )
		return false;
	PX = Tex.USize * 0.5 * (1 + (L.Y / L.X) / h);
	PY = Tex.VSize * 0.5 - Tex.USize * 0.5 * (L.Z / L.X) / h;
	return true;
}

// text at head-space point (right, up) in meters, Align 0 left / 1 centre / 2 right
function HudText(ScriptedTexture Tex, vector Loc, rotator Rot, float Right, float Up, string T, Font F, color C, int Align)
{
	local vector X, Y, Z, P;
	local float PX, PY;
	local int W, H;
	local color Sh;

	GetAxes(VRHeadRot, X, Y, Z);
	P = VRHeadWorld + (X * HudDistance + Y * Right * HudSpread + Z * (Up - HudLower) * HudSpread) * UUPerMeter;
	if ( !HudProject(Tex, P, Loc, Rot, PX, PY) )
		return;
	Tex.TextSize(T, F, W, H);
	if ( Align == 1 )
		PX -= W / 2;
	else if ( Align == 2 )
		PX -= W;
	PY -= H / 2;
	Sh.R = 0; Sh.G = 0; Sh.B = 0; Sh.A = 255;
	Tex.DrawText(PX + 2, PY + 2, T, F, Sh);
	Tex.DrawText(PX, PY, T, F, C);
}

function color HudColor(byte R, byte G, byte B)
{
	local color C;
	C.R = R; C.G = G; C.B = B; C.A = 255;
	return C;
}

// head-space point (right, up in meters) -> pixel in this eye
function bool HudPoint(ScriptedTexture Tex, vector Loc, rotator Rot, float Right, float Up, out float PX, out float PY)
{
	local vector X, Y, Z, P;
	GetAxes(VRHeadRot, X, Y, Z);
	P = VRHeadWorld + (X * HudDistance + Y * Right * HudSpread + Z * (Up - HudLower) * HudSpread) * UUPerMeter;
	return HudProject(Tex, P, Loc, Rot, PX, PY);
}

// UT's HUD digits (HudContent.Generic.HUD, 38x38 cells at x = 39*n, n = 10 is the minus sign).
// Align 0: starts at the point, 2: ends at it. Returns the width drawn.
function float HudDigits(ScriptedTexture Tex, float PX, float PY, int Value, float Size, color C, int Align)
{
	return HudDigitString(Tex, PX, PY, string(Value), Size, C, Align);
}

// the same for a string of digits, '-' and ':' (UT's timer colon, HUD.TimerDigitSpacer); Align 1 centres it
function float HudDigitString(ScriptedTexture Tex, float PX, float PY, string S, float Size, color C, int Align)
{
	local int i, d;
	local float W, X;
	local string Ch;
	local Material M;

	M = Material(DynamicLoadObject("HudContent.Generic.HUD", class'Material'));
	for ( i = 0; i < Len(S); i++ )
		if ( Mid(S, i, 1) == ":" )
			W += Size * 0.35;
		else
			W += Size * 0.8;
	if ( Align == 2 )
		PX -= W;
	else if ( Align == 1 )
		PX -= W / 2;
	X = PX;
	for ( i = 0; i < Len(S); i++ )
	{
		Ch = Mid(S, i, 1);
		if ( Ch == ":" )
		{
			Tex.DrawTile(X + Size * 0.07, PY - Size * 0.3, Size * 0.21, Size * 0.55, 495, 91, 8, 21, M, C);
			X += Size * 0.35;
			continue;
		}
		if ( Ch == "-" )
			d = 10;
		else
			d = Asc(Ch) - 48;
		Tex.DrawTile(X, PY - Size / 2, Size, Size, 39 * d, 0, 38, 38, M, C);
		X += Size * 0.8;
	}
	return W;
}

// the match clock, top centre: time left with a time limit, else time played (HudCDeathMatch.DrawTimer)
function DrawVRClock(ScriptedTexture Tex, vector Loc, rotator Rot, Material HudTex, float Size, float Icon)
{
	local int Secs, H;
	local string S;
	local float PX, PY, W;

	if ( GameReplicationInfo == None || !HudPoint(Tex, Loc, Rot, 0, HudTopUp, PX, PY) )
		return;
	if ( GameReplicationInfo.TimeLimit != 0 )
		Secs = GameReplicationInfo.RemainingTime;
	else
		Secs = GameReplicationInfo.ElapsedTime;
	H = Secs / 3600;
	Secs -= H * 3600;
	S = Right("0" $ (Secs / 60), 2) $ ":" $ Right("0" $ int(Secs % 60), 2);
	if ( H > 0 )
		S = H $ ":" $ S;
	// the clock icon left of the digits, the pair centred on the point
	W = Size * 0.8 * 4 + Size * 0.35;
	if ( H > 0 )
		W += Size * (0.8 * Len(string(H)) + 0.35);
	HudIcon(Tex, PX - (W + Icon * 1.1) / 2 + Icon / 2, PY, HudTex, 150, 356, 34, 33, Icon, HudColor(255, 255, 255));
	HudDigitString(Tex, PX - (W + Icon * 1.1) / 2 + Icon * 1.1, PY, S, Size, HudColor(255, 255, 255), 0);
}

function HudIcon(ScriptedTexture Tex, float PX, float PY, Material M, float U, float V, float UL, float VL, float Size, color C)
{
	local float W;
	if ( M == None || VL <= 0 )
		return;
	W = Size * UL / VL;
	Tex.DrawTile(PX - W / 2, PY - Size / 2, W, Size, U, V, UL, VL, M, C);
}

function DrawVRHud(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local float PX, PY, Big, Small, Icon;
	local int i, Rank, Spread, Best, Ammo;
	local color White, Low, Yellow;
	local Material HudTex;
	local class<Ammunition> AC;
	local GameReplicationInfo G;

	if ( HudBig == None )
		HudBig = Font(DynamicLoadObject("UT2003Fonts.FontEurostile37", class'Font'));
	HudTex = Material(DynamicLoadObject("HudContent.Generic.HUD", class'Material'));
	if ( HudTex == None )
		return;
	White = HudColor(255, 255, 255);
	Low = HudColor(255, 60, 60);
	Yellow = HudColor(255, 255, 0);
	Big = Tex.USize * 0.030 * HudSize;
	Small = Tex.USize * 0.024 * HudSize;
	Icon = Tex.USize * 0.036 * HudSize;

	if ( IsCinematic() )
		return;
	// UT's own scoreboard is up (a panel from the proxy): as in 2D, no HUD under it, messages only if it wants them
	if ( VRHUD(myHUD) != None && VRHUD(myHUD).ScoreFrame > 0 && VRHUD(myHUD).OverlayKind == 1 )
	{
		// (the typing prompt is drawn with the messages: shown under the scoreboard too)
		if ( bVRMessages && ((myHUD.ScoreBoard != None && myHUD.ScoreBoard.bDisplayMessages)
			|| (myHUD.PlayerConsole != None && myHUD.PlayerConsole.bTyping)) )
			VRHUD(myHUD).DrawVRMessages(self, Tex, Loc, Rot);
		return;
	}
	// in a vehicle: UT's crosshairs where its gun hits (with the original HUD), else the VR crosshair / laser
	if ( Vehicle(Pawn) != None && UsingOriginalHud() && ASVehicle(Pawn) == None )
	{
		if ( Markers == None )
			Markers = new class'VRGameMarkers';
		if ( !VRHUD(myHUD).WantScores(self) )
			Markers.DrawONSCrosshair(self, VRHUD(myHUD).Shadow, Tex, Loc, Rot);
	}
	else if ( Vehicle(Pawn) != None )
		DrawVehicleCrosshair(Tex, Loc, Rot);
	if ( HudBig != None && !bVRScoreboardOriginal && (bShowVRScores || (myHUD != None && myHUD.bShowScoreBoard)) )
		DrawVRScores(Tex, Loc, Rot);
	// (not while spectating with UT's own spectator bar: it has no clock either; nor with the game type's own HUD)
	if ( bVRClock && !(bVRScoreboardOriginal && IsVRSpectating()) && !UsingOriginalHud() )
		DrawVRClock(Tex, Loc, Rot, HudTex, Small, Icon * Small / Big);
	// (with the game type's HUD layer up, the messages are drawn into it, on top of the HUD)
	if ( bVRMessages && VRHUD(myHUD) != None && !(VRHUD(myHUD).OverlayKind == 3 && VRHUD(myHUD).ScoreFrame > 0) )
		VRHUD(myHUD).DrawVRMessages(self, Tex, Loc, Rot);

	if ( Pawn == None )
	{
		// with the game type's own HUD its own screen says it (the scoreboard while dead: "press fire to respawn")
		if ( HudBig != None && !UsingOriginalHud() )
		{
			// below the scoreboard, which UT shows while you're dead
			if ( bShowVRScores || (myHUD != None && myHUD.bShowScoreBoard) )
				PY = -0.33;
			else
				PY = 0.1;
			// spectating: fire looks through the next player's eyes; joining goes through the Esc menu (with
			// bVRScoreboardOriginal UT's own spectator bar is shown instead, as a panel)
			if ( IsVRSpectating() && bVRScoreboardOriginal )
			{
			}
			else if ( IsVRSpectating() )
			{
				HudText(Tex, Loc, Rot, 0, PY, "Spectating", HudBig, White, 1);
				if ( bKeyboardMouse )
					HudText(Tex, Loc, Rot, 0, PY - 0.08, "Click: next player    Esc menu: join", HudBig, White, 1);
				else
					HudText(Tex, Loc, Rot, 0, PY - 0.08, "Trigger: next player    Esc menu: join", HudBig, White, 1);
			}
			else if ( !IsInState('Dead') )
			{
				if ( bKeyboardMouse )
					HudText(Tex, Loc, Rot, 0, PY, "Click to join", HudBig, White, 1);
				else
					HudText(Tex, Loc, Rot, 0, PY, "Pull the trigger to join", HudBig, White, 1);
			}
			else if ( bKeyboardMouse )
				HudText(Tex, Loc, Rot, 0, PY, "Click to respawn", HudBig, White, 1);
			else
				HudText(Tex, Loc, Rot, 0, PY, "Pull the trigger to respawn", HudBig, White, 1);
		}
		return;
	}

	// the game type's own HUD is in the headset (captured, VRHUD.Shadow): its health, ammo, scores and timers instead;
	// what it points at in the world is drawn here, in 3D
	if ( UsingOriginalHud() )
	{
		// under the scoreboard (part of the layer now) nothing points into the world, as in 2D
		if ( VRHUD(myHUD).WantScores(self) )
			return;
		if ( Markers == None )
			Markers = new class'VRGameMarkers';
		if ( HUD_Assault(VRHUD(myHUD).Shadow) != None )
			Markers.DrawAssault(self, HUD_Assault(VRHUD(myHUD).Shadow), Tex, Loc, Rot);
		if ( ASVehicle(Pawn) != None )
			Markers.DrawASVehicleCrosshair(self, ASVehicle(Pawn), Tex, Loc, Rot);
		if ( ASVehicle_SpaceFighter(Pawn) != None && HUD_Assault(VRHUD(myHUD).Shadow) != None )
			Markers.DrawFighterTarget(self, ASVehicle_SpaceFighter(Pawn), HUD_Assault(VRHUD(myHUD).Shadow), Tex, Loc, Rot);
		return;
	}

	if ( bCalibGun )
	{
		// debug: HUD centre and +-0.3 m marks (head space), to measure where the HUD frame lands in the eye
		if ( HudPoint(Tex, Loc, Rot, 0, 0, PX, PY) )
			Tex.DrawTile(PX - 6, PY - 6, 12, 12, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', HudColor(0, 255, 0));
		if ( HudPoint(Tex, Loc, Rot, 0, 0.3, PX, PY) )
			Tex.DrawTile(PX - 6, PY - 6, 12, 12, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', HudColor(255, 0, 255));
		if ( HudPoint(Tex, Loc, Rot, 0, -0.3, PX, PY) )
			Tex.DrawTile(PX - 6, PY - 6, 12, 12, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', HudColor(255, 0, 255));
		Log("VR hud: headrot="$VRHeadRot$" eyerot="$Rot$" aim="$Rotation$" headpos="$HeadPos$" eyeloc-head="$(Loc - VRHeadWorld), 'UT2004VR');
	}

	// lower left: health cross + health
	if ( HudPoint(Tex, Loc, Rot, -0.62, HudBottomUp, PX, PY) )
	{
		HudIcon(Tex, PX, PY, HudTex, 74, 165, 49, 51, Icon, White);
		if ( Pawn.Health < 30 )
			HudDigits(Tex, PX + Icon * 0.7, PY, Pawn.Health, Big, Low, 0);
		else
			HudDigits(Tex, PX + Icon * 0.7, PY, Pawn.Health, Big, White, 0);
	}

	// lower right: ammo + the current ammo's icon
	if ( Pawn.Weapon != None && Pawn.Weapon.AmmoClass[0] != None && HudPoint(Tex, Loc, Rot, 0.62, HudBottomUp, PX, PY) )
	{
		AC = Pawn.Weapon.AmmoClass[0];
		HudIcon(Tex, PX, PY, AC.default.IconMaterial, AC.default.IconCoords.X1, AC.default.IconCoords.Y1,
			AC.default.IconCoords.X2 - AC.default.IconCoords.X1, AC.default.IconCoords.Y2 - AC.default.IconCoords.Y1, Icon, White);
		Ammo = Pawn.Weapon.AmmoAmount(0);
		if ( Ammo <= 5 )
			HudDigits(Tex, PX - Icon * 0.8, PY, Ammo, Big, Low, 2);
		else
			HudDigits(Tex, PX - Icon * 0.8, PY, Ammo, Big, White, 2);
	}

	// upper right: adrenaline pill + adrenaline
	if ( bAdrenalineEnabled && HudPoint(Tex, Loc, Rot, 0.62, HudTopUp, PX, PY) )
	{
		HudIcon(Tex, PX, PY, HudTex, 113, 38, 52, 68, Icon, White);
		if ( Adrenaline >= AdrenalineMax )
			HudDigits(Tex, PX - Icon * 0.6, PY, int(Adrenaline), Big, Yellow, 2);
		else
			HudDigits(Tex, PX - Icon * 0.6, PY, int(Adrenaline), Big, White, 2);
	}

	// upper left: frags (big), spread to the leader (+ when you lead) and rank
	G = GameReplicationInfo;
	if ( PlayerReplicationInfo != None && G != None && HudPoint(Tex, Loc, Rot, -0.62, HudTopUp, PX, PY) )
	{
		Rank = 1;
		Best = -100000;
		for ( i = 0; i < G.PRIArray.Length; i++ )
		{
			if ( G.PRIArray[i] == None || G.PRIArray[i] == PlayerReplicationInfo || G.PRIArray[i].bOnlySpectator )
				continue;
			if ( G.PRIArray[i].Score > PlayerReplicationInfo.Score )
				Rank++;
			if ( G.PRIArray[i].Score > Best )
				Best = G.PRIArray[i].Score;
		}
		if ( Best == -100000 )
			Spread = 0;
		else
			Spread = int(PlayerReplicationInfo.Score) - Best;   // > 0: your lead over the next best
		// frags (big), then the spread to the leader and your rank (stock layout, no icon)
		HudDigits(Tex, PX - Icon * 0.5, PY, int(PlayerReplicationInfo.Score), Big * 1.2, White, 0);
		if ( HudPoint(Tex, Loc, Rot, -0.62, HudTopUp - 0.09, PX, PY) )
		{
			if ( Spread > 0 && HudBig != None )
				Tex.DrawText(PX - Icon * 0.5 - Small * 0.7, PY - Small * 0.6, "+", HudBig, White);
			HudDigits(Tex, PX - Icon * 0.5, PY, Spread, Small, White, 0);
		}
		if ( HudPoint(Tex, Loc, Rot, -0.62, HudTopUp - 0.17, PX, PY) )
			HudDigits(Tex, PX - Icon * 0.5, PY, Rank, Small, White, 0);
	}
}

// ---------------------------------------------------------------------------
// UT's game messages in VR: HudBase keeps them in two queues (LocalMessages: pickups, first blood, sprees, multi
// kills, critical events; TextMessages: kills, chat, joins), but only draws them from its 2D PostRender, which the
// eyes skip. Here they go onto a virtual screen whose corners are the VR HUD's corners, at the HUD's depth, with the
// message classes' own positions, pivots, stacking, colours, fades and UT's font sizes for that screen's pixel width.
// VRHUD.DrawVRMessages draws them; these are its helpers.
// ---------------------------------------------------------------------------

// screen position (0..1, as on the 2D HUD) -> pixel in this eye, on the VR HUD's rectangle
function bool MsgPoint(ScriptedTexture Tex, vector Loc, rotator Rot, float SX, float SY, out float PX, out float PY)
{
	return HudPoint(Tex, Loc, Rot, -0.62 + SX * 1.24, HudTopUp - SY * (HudTopUp - HudBottomUp), PX, PY);
}

// UT's font size steps for a screen this wide (HUD.GetFontSizeIndex / GetConsoleFont), minus the VR boost
function int MsgFontSteps(float VW)
{
	local int n;
	if ( VW >= 512 ) n++;
	if ( VW >= 640 ) n++;
	if ( VW >= 800 ) n++;
	if ( VW >= 1024 ) n++;
	if ( VW >= 1280 ) n++;
	if ( VW >= 1600 ) n++;
	return n + VRMessageFontBoost;
}

function MsgText(ScriptedTexture Tex, float X, float Y, string T, Font F, color C)
{
	local color Sh;
	Sh.R = 0; Sh.G = 0; Sh.B = 0; Sh.A = C.A;
	Tex.DrawText(X + 2, Y + 2, T, F, Sh);
	Tex.DrawText(X, Y, T, F, C);
}

// in a vehicle: a crosshair where its weapon aims (UT's camera aim, traced into the world), drawn at that point,
// so it has the right depth in both eyes
// the gun you fire in a vehicle: the driver's active weapon, or the turret's on a gunner seat
function ONSWeapon VehicleGun()
{
	if ( ONSVehicle(Pawn) != None && ONSVehicle(Pawn).ActiveWeapon < ONSVehicle(Pawn).Weapons.Length )
		return ONSVehicle(Pawn).Weapons[ONSVehicle(Pawn).ActiveWeapon];
	if ( ONSWeaponPawn(Pawn) != None )
		return ONSWeaponPawn(Pawn).Gun;
	return None;
}

function bool VehicleAimTrace(out vector Start, out vector Dir, out vector HitL, out ONSWeapon W, out byte bHit)
{
	local Actor A;
	local vector End, HitN, S;
	local float Range;
	local int i;

	W = VehicleGun();
	if ( W != None )
	{
		W.CalcWeaponFire();
		Start = W.WeaponFireLocation;
		Dir = vector(W.WeaponFireRotation);
		Range = W.TraceRange;
	}
	else if ( ONSVehicle(Pawn) != None || ONSWeaponPawn(Pawn) != None )
		return false;   // a seat without a gun (the Hellbender's driver)
	else
	{
		Start = VRHeadWorld;
		Dir = vector(VRHeadRot);
	}
	if ( Range < 1000 )
		Range = 20000;
	End = Start + Dir * Range;
	HitL = End;
	bHit = 0;
	S = Start;
	// skip your own vehicle and the guns bolted onto it
	for ( i = 0; i < 4; i++ )
	{
		A = Pawn.Trace(HitL, HitN, End, S, true);
		if ( A == None )
		{
			HitL = End;
			break;
		}
		if ( A != Pawn && A.Base != Pawn && A.Owner != Pawn && A != W
			&& !(ONSWeaponPawn(Pawn) != None && (A == ONSWeaponPawn(Pawn).VehicleBase || A.Base == ONSWeaponPawn(Pawn).VehicleBase)) )
		{
			bHit = 1;
			break;
		}
		S = HitL + Dir * 8;
	}
	return true;
}

// where the vehicle's shots land: UT turns its guns toward what you look at (it traces from the camera, our head),
// but turrets lag and stop at their limits, so trace from the gun's own muzzle along its own aim. Green when the
// gun can reach what you look at, orange when it can't. (With bVehicleLaser the laser shows this instead.)
function DrawVehicleCrosshair(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local ONSWeapon W;
	local vector Start, HitL, Dir;
	local float PX, PY, S;
	local color C, Sh;
	local byte bHit;

	if ( bVehicleLaser || !VehicleAimTrace(Start, Dir, HitL, W, bHit) )
		return;
	if ( !HudProject(Tex, HitL, Loc, Rot, PX, PY) )
		return;
	S = Tex.USize * 0.003;
	if ( W == None || W.bCorrectAim || !W.bShowAimCrosshair )
		C = HudColor(120, 255, 120);
	else
		C = HudColor(255, 160, 40);
	Sh = HudColor(0, 0, 0);
	// four ticks around a dot, with a dark outline
	Tex.DrawTile(PX - S * 3.2 - 1, PY - S * 0.35 - 1, S * 2 + 2, S * 0.7 + 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Sh);
	Tex.DrawTile(PX + S * 1.2 - 1, PY - S * 0.35 - 1, S * 2 + 2, S * 0.7 + 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Sh);
	Tex.DrawTile(PX - S * 0.35 - 1, PY - S * 3.2 - 1, S * 0.7 + 2, S * 2 + 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Sh);
	Tex.DrawTile(PX - S * 0.35 - 1, PY + S * 1.2 - 1, S * 0.7 + 2, S * 2 + 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Sh);
	Tex.DrawTile(PX - S * 3.2, PY - S * 0.35, S * 2, S * 0.7, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', C);
	Tex.DrawTile(PX + S * 1.2, PY - S * 0.35, S * 2, S * 0.7, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', C);
	Tex.DrawTile(PX - S * 0.35, PY - S * 3.2, S * 0.7, S * 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', C);
	Tex.DrawTile(PX - S * 0.35, PY + S * 1.2, S * 0.7, S * 2, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', C);
	Tex.DrawTile(PX - S * 0.4, PY - S * 0.4, S * 0.8, S * 0.8, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', C);
	if ( bDebugLog && Level.TimeSeconds > NextCrossLog )
	{
		NextCrossLog = Level.TimeSeconds + 1.0;
		Log("UT2004VR: vehicle aim "$W$" from "$Start$" hit "$bHit$" at "$HitL$" ("$int(VSize(HitL - Start))$" uu) on eye "$int(PX)$","$int(PY)$" of "$Tex.USize$" correct "$(W != None && W.bCorrectAim), 'UT2004VR');
	}
}

// in a vehicle: next/previous seat (driver, then the gunner turrets), only the free ones. UT's mouse wheel would
// switch to the chase camera instead, which drops you out of the cockpit.
function VehicleSeatCycle(int Dir)
{
	local ONSVehicle B;
	local int Cur, N, S, k;

	B = ONSVehicle(Pawn);
	if ( ONSWeaponPawn(Pawn) != None )
		B = ONSWeaponPawn(Pawn).VehicleBase;
	if ( B == None )
		return;
	N = B.WeaponPawns.Length + 1;
	Cur = 0;
	for ( k = 0; k < B.WeaponPawns.Length; k++ )
		if ( B.WeaponPawns[k] == Pawn )
			Cur = k + 1;
	for ( k = 1; k < N; k++ )
	{
		S = Cur + Dir * k;
		while ( S < 0 ) S += N;
		while ( S >= N ) S -= N;
		if ( (S == 0 && B.Driver == None) || (S > 0 && B.WeaponPawns[S - 1] != None && B.WeaponPawns[S - 1].Driver == None) )
		{
			Log("UT2004VR: seat "$(Cur + 1)$" -> "$(S + 1)$" of "$N$" in "$B.Class.Name, 'UT2004VR');
			Pawn.SwitchWeapon(S + 1);
			return;
		}
	}
}

exec function NextWeapon()
{
	// Onslaught vehicles: the wheel changes seats; Assault's keep UT's own (space fighters: the next target,
	// turrets: the next turret of the group)
	if ( Vehicle(Pawn) != None && ASVehicle(Pawn) == None && VRActive() )
		VehicleSeatCycle(1);
	else
		Super.NextWeapon();
}

exec function PrevWeapon()
{
	// Onslaught vehicles: the wheel changes seats; Assault's keep UT's own (space fighters: the next target,
	// turrets: the next turret of the group)
	if ( Vehicle(Pawn) != None && ASVehicle(Pawn) == None && VRActive() )
		VehicleSeatCycle(-1);
	else
		Super.PrevWeapon();
}

// debug: toggle behind view as F does
exec function VRBehind()
{
	BehindView(!bBehindView);
	Log("UT2004VR: behind view "$bBehindView, 'UT2004VR');
}

// debug: what the mouse wheel does, from a TestExec line
exec function VRNextWeapon()
{
	if ( Pawn != None )
		Pawn.NextWeapon();
}

// Riding the guided Redeemer you look out through a round window at its tip: black around it, a red-lit rim with
// markings (2D's scope overlay). It sits RedeemerWindowDist ahead along the flight, fixed to the warhead, so each eye
// sees it from its own spot (it has depth) and turning your head looks at the rim and the dark inside.
function DrawRedeemerWindow(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local rotator FlightR;
	local vector C, L;
	local float h, PX, PY, R, T, X0, Y0, X1, Y1;
	local color K;
	local RedeemerWarhead W;

	K = HudColor(0, 0, 0);
	FlightR = Pawn.Rotation;
	if ( !bRedeemerRoll )
		FlightR.Roll = 0;
	// the window's centre: ahead of where your head was at launch (the eyes ride the warhead from there)
	C = Pawn.Location + vector(FlightR) * RedeemerWindowDist * UUPerMeter;
	h = Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
	L = (C - Loc) << Rot;
	if ( L.X <= 1 )
	{
		Tex.DrawTile(0, 0, Tex.USize, Tex.VSize, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
		return;
	}
	PX = Tex.USize * 0.5 * (1 + (L.Y / L.X) / h);
	PY = Tex.VSize * 0.5 - Tex.USize * 0.5 * (L.Z / L.X) / h;
	R = Tex.USize * 0.5 * (RedeemerWindowDist * UUPerMeter * Tan(RedeemerWindowDeg * 0.5 * 3.14159265 / 180.0) / L.X) / h;
	W = RedeemerWarhead(Pawn);
	if ( W != None && W.OuterEdgeShader != None )
	{
		// UT's own scope overlay (Warhead.DrawHUD, square case): its circle spans the square
		T = R;
		X0 = PX - T; Y0 = PY - T; X1 = PX + T; Y1 = PY + T;
		DrawWarheadScope(Tex, W, X0, Y0, 2 * T);
	}
	else
	{
		T = R / 0.93;   // our texture's window edge is at 0.93 of its half-size
		X0 = PX - T; Y0 = PY - T; X1 = PX + T; Y1 = PY + T;
		Tex.DrawTile(X0, Y0, X1 - X0, Y1 - Y0, 0, 0, 512, 512, Texture'VRPorthole', HudColor(255, 255, 255));
	}
	// black all around it
	if ( Y0 > 0 )
		Tex.DrawTile(0, 0, Tex.USize, Y0, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
	if ( Y1 < Tex.VSize )
		Tex.DrawTile(0, Y1, Tex.USize, Tex.VSize - Y1, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
	if ( X0 > 0 )
		Tex.DrawTile(0, FMax(Y0, 0), X0, FMin(Y1, Tex.VSize) - FMax(Y0, 0), 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
	if ( X1 < Tex.USize )
		Tex.DrawTile(X1, FMax(Y0, 0), Tex.USize - X1, FMin(Y1, Tex.VSize) - FMax(Y0, 0), 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', K);
}

// the warhead's scope materials as 2D draws them (four mirrored quadrants of the edge and inner scope, the outer
// scope ring over all, the two altitude bars), in a square of side S at X0, Y0
function DrawWarheadScope(ScriptedTexture Tex, RedeemerWarhead W, float X0, float Y0, float S)
{
	local float Q;
	local color Wh;
	Wh = HudColor(255, 255, 255);
	Q = S * 0.5;
	Tex.DrawTile(X0, Y0, Q, Q, 0, 0, 512, 512, W.OuterEdgeShader, Wh);
	Tex.DrawTile(X0 + Q, Y0, Q, Q, 512, 0, -512, 512, W.OuterEdgeShader, Wh);
	Tex.DrawTile(X0, Y0 + Q, Q, Q, 0, 512, 512, -512, W.OuterEdgeShader, Wh);
	Tex.DrawTile(X0 + Q, Y0 + Q, Q, Q, 512, 512, -512, -512, W.OuterEdgeShader, Wh);
	Tex.DrawTile(X0, Y0, Q, Q, 0, 0, 512, 512, W.InnerScopeShader, Wh);
	Tex.DrawTile(X0 + Q, Y0, Q, Q, 512, 0, -512, 512, W.InnerScopeShader, Wh);
	Tex.DrawTile(X0, Y0 + Q, Q, Q, 0, 512, 512, -512, W.InnerScopeShader, Wh);
	Tex.DrawTile(X0 + Q, Y0 + Q, Q, Q, 512, 512, -512, -512, W.InnerScopeShader, Wh);
	Tex.DrawTile(X0, Y0, S, S, 0, 0, 1024, 1024, W.OuterScopeShader, Wh);
	if ( W.AltitudeFinalBlend != None )
	{
		Tex.DrawTile(X0 + S * 383.0 / 1024.0, Y0 + S * 451.0 / 1024.0, S / 8, S / 8, 0, 0, 128, 128, W.AltitudeFinalBlend, Wh);
		Tex.DrawTile(X0 + S * (383.0 + 2 * (512 - 383) - 128) / 1024.0, Y0 + S * 451.0 / 1024.0, S / 8, S / 8, 128, 0, -128, 128, W.AltitudeFinalBlend, Wh);
	}
}

// scoreboard panel (left X / VRScores, or UT's own show-scores key): players by frags, you in yellow
function DrawVRScores(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local array<PlayerReplicationInfo> L;
	local PlayerReplicationInfo T;
	local GameReplicationInfo G;
	local ConstantColor CC;
	local FinalBlend FB;
	local float X0, Y0, X1, Y1, Up, Step, CX, CY;
	local int i, j, Rows, TW, TH;
	local color White, Grey, Yellow, C;
	local string Head;

	G = GameReplicationInfo;
	if ( G == None )
		return;
	for ( i = 0; i < G.PRIArray.Length; i++ )
		if ( G.PRIArray[i] != None && !G.PRIArray[i].bOnlySpectator )
			L[L.Length] = G.PRIArray[i];
	// most frags first, then fewest deaths
	for ( i = 0; i < L.Length; i++ )
		for ( j = i + 1; j < L.Length; j++ )
			if ( L[j].Score > L[i].Score || (L[j].Score == L[i].Score && L[j].Deaths < L[i].Deaths) )
			{
				T = L[i]; L[i] = L[j]; L[j] = T;
			}
	Rows = Min(L.Length, 12);
	Step = 0.055;

	if ( ScoresBack == None )
	{
		CC = new(None) class'ConstantColor';
		CC.Color.R = 0; CC.Color.G = 0; CC.Color.B = 0; CC.Color.A = 170;
		FB = new(None) class'FinalBlend';
		FB.Material = CC;
		FB.FrameBufferBlending = FB_AlphaBlend;
		ScoresBack = FB;
	}
	// laid out in font units around one projected centre point (so the whole panel sits at the HUD's stereo depth)
	if ( !HudPoint(Tex, Loc, Rot, 0, 0.05, CX, CY) )
		return;
	PickScoresFont(Tex);
	Tex.TextSize("Mg", ScoresFont, TW, TH);
	Step = TH * 1.15;
	X0 = CX - TH * 8.5;
	X1 = CX + TH * 8.5;
	Y0 = CY - Step * (Rows + 2.6) / 2;
	Y1 = CY + Step * (Rows + 2.6) / 2;
	Tex.DrawTile(X0, Y0, X1 - X0, Y1 - Y0, 0, 0, 1, 1, ScoresBack, HudColor(255, 255, 255));

	White = HudColor(255, 255, 255);
	Grey = HudColor(170, 170, 170);
	Yellow = HudColor(255, 255, 0);
	Head = G.GameName;
	if ( G.GoalScore > 0 )
		Head = Head $ "  -  frag limit " $ G.GoalScore;
	if ( G.TimeLimit > 0 )
		Head = Head $ "  -  " $ (G.RemainingTime / 60) $ ":" $ Right("0" $ int(G.RemainingTime % 60), 2) $ " left";
	Up = Y0 + Step * 0.3;
	ScoreText(Tex, CX, Up, Head, White, 1);
	Up += Step * 1.2;
	ScoreText(Tex, CX - TH * 8, Up, "Player", Grey, 0);
	ScoreText(Tex, CX + TH * 4.5, Up, "Frags", Grey, 2);
	ScoreText(Tex, CX + TH * 8, Up, "Deaths", Grey, 2);
	for ( i = 0; i < Rows; i++ )
	{
		Up += Step;
		if ( L[i] == PlayerReplicationInfo )
			C = Yellow;
		else if ( L[i].Team != None && L[i].Team.TeamIndex == 0 )
			C = HudColor(255, 110, 110);
		else if ( L[i].Team != None && L[i].Team.TeamIndex == 1 )
			C = HudColor(120, 160, 255);
		else
			C = White;
		ScoreText(Tex, CX - TH * 8, Up, (i + 1) $ ". " $ L[i].PlayerName, C, 0);
		ScoreText(Tex, CX + TH * 4.5, Up, string(int(L[i].Score)), C, 2);
		ScoreText(Tex, CX + TH * 8, Up, string(int(L[i].Deaths)), C, 2);
	}
}

// the biggest Eurostile whose 17-line-height-wide panel fits ScoresWidthDeg at this eye resolution (fonts have a
// fixed pixel size, so a bigger eye texture needs a bigger font for the same angular size)
function PickScoresFont(ScriptedTexture Tex)
{
	local int Sizes[8], i, TW, TH;
	local float h, WantPx;
	local Font F;

	if ( ScoresFont != None && ScoresFontFor == Tex.USize )
		return;
	Sizes[0] = 37; Sizes[1] = 29; Sizes[2] = 24; Sizes[3] = 21; Sizes[4] = 17; Sizes[5] = 14; Sizes[6] = 12; Sizes[7] = 11;
	h = Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
	WantPx = Tex.USize * 0.5 * 2 * Tan(ScoresWidthDeg * 0.5 * 3.14159265 / 180.0) / h;
	for ( i = 0; i < 8; i++ )
	{
		F = Font(DynamicLoadObject("UT2003Fonts.FontEurostile" $ Sizes[i], class'Font'));
		if ( F == None )
			continue;
		ScoresFont = F;
		Tex.TextSize("Mg", F, TW, TH);
		if ( TH * 17 <= WantPx )
			break;
	}
	if ( ScoresFont == None )
		ScoresFont = HudBig;
	ScoresFontFor = Tex.USize;
	Log("UT2004VR: scoreboard font "$ScoresFont$" (line "$TH$" px, panel "$(TH * 17)$" of "$WantPx$" px)", 'UT2004VR');
}

// shadowed text at a pixel position; Align 0 left / 1 centre / 2 right
function ScoreText(ScriptedTexture Tex, float X, float Y, string T, color C, int Align)
{
	local int W, H;
	Tex.TextSize(T, ScoresFont, W, H);
	if ( Align == 1 )
		X -= W / 2;
	else if ( Align == 2 )
		X -= W;
	Tex.DrawText(X + 2, Y + 2, T, ScoresFont, HudColor(0, 0, 0));
	Tex.DrawText(X, Y, T, ScoresFont, C);
}

// yellow boxes where the math (square pixels, horizontal FOV) puts the calibration markers
function DrawCalibTex(ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local int i;
	local vector L;
	local float h, px, py;
	local color Y;

	Y.R = 255; Y.G = 255; Y.B = 0; Y.A = 255;
	h = Tan(EyeFOV * 0.5 * 3.14159265 / 180.0);
	for ( i = 0; i < 5; i++ )
	{
		L = (CalibPts[i] - Loc) << Rot;
		if ( L.X <= 1 )
			continue;
		px = Tex.USize * 0.5 * (1 + (L.Y / L.X) / h);
		py = Tex.VSize * 0.5 - Tex.USize * 0.5 * (L.Z / L.X) / h;
		Tex.DrawTile(px - 16, py - 16, 32, 3, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Y);
		Tex.DrawTile(px - 16, py + 13, 32, 3, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Y);
		Tex.DrawTile(px - 16, py - 16, 3, 32, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Y);
		Tex.DrawTile(px + 13, py - 16, 3, 32, 0, 0, 2, 2, Texture'Engine.WhiteSquareTexture', Y);
	}
}

// Alyx-style recenter: re-measure height and face the open direction again
exec function VRRecenter()
{
	bNeedHeight = true;
	bForceHeight = true;
	WornTime = 1.0;
	CalibSum = 0;
	CalibCount = 0;
	CalibFwdSum = vect(0,0,0);
	ChairCount = 0;
	bChairMeasured = false;   // recenter: take the chair forward and pitch again
	bChairFromGaze = true;    // ... from where you look now, not the seated calibration
	bNeedSpawnFacing = true;
	bAnchorValid = false;
	BlinkUntil = Level.TimeSeconds + 0.15;
}

function LoadTuning()
{
	Grips = class'VRTuning'.default.Grips;
	GripCacheClass = None;
	VehSeats = class'VRTuning'.default.VehSeats;
	KBMGrips = class'VRTuning'.default.KBMGrips;
	if ( !class'VRTuning'.default.bSaved )
		return;
	GunOffset = class'VRTuning'.default.GunOffset;
	GunScale = class'VRTuning'.default.GunScale;
	GunPitchOffset = class'VRTuning'.default.GunPitchOffset;
	SnapTurnDegrees = class'VRTuning'.default.SnapTurnDegrees;
	bSmoothTurn = class'VRTuning'.default.bSmoothTurn;
	bHandRelativeMove = class'VRTuning'.default.bHandRelativeMove;
	MoveSpeedScale = class'VRTuning'.default.MoveSpeedScale;
	UUPerMeter = class'VRTuning'.default.UUPerMeter;
	EyeHeightBonus = class'VRTuning'.default.EyeHeightBonus;
	bKeyboardMouse = class'VRTuning'.default.bKeyboardMouse;   // the only saved copy (VRKeyboard)
	bMatchGameHeight = class'VRTuning'.default.bMatchGameHeight || class'VRTuning'.default.EyeHeightBonus == 0;
	if ( class'VRTuning'.default.FlipGuns.Length > 0 )
		FlipGuns = class'VRTuning'.default.FlipGuns;
}

function SaveTuning()
{
	class'VRTuning'.default.bSaved = true;
	class'VRTuning'.default.GunOffset = GunOffset;
	class'VRTuning'.default.GunScale = GunScale;
	class'VRTuning'.default.GunPitchOffset = GunPitchOffset;
	class'VRTuning'.default.SnapTurnDegrees = SnapTurnDegrees;
	class'VRTuning'.default.bSmoothTurn = bSmoothTurn;
	class'VRTuning'.default.bHandRelativeMove = bHandRelativeMove;
	class'VRTuning'.default.MoveSpeedScale = MoveSpeedScale;
	class'VRTuning'.default.UUPerMeter = UUPerMeter;
	class'VRTuning'.default.EyeHeightBonus = EyeHeightBonus;
	class'VRTuning'.default.bKeyboardMouse = bKeyboardMouse;
	class'VRTuning'.default.bMatchGameHeight = bMatchGameHeight;
	class'VRTuning'.default.FlipGuns = FlipGuns;
	class'VRTuning'.default.Grips = Grips;
	class'VRTuning'.default.VehSeats = VehSeats;
	class'VRTuning'.default.KBMGrips = KBMGrips;
	class'VRTuning'.static.StaticSaveConfig();
	ClientMessage("UT2004VR: saved. Gun offset "$GunOffset$", scale "$GunScale$", pitch "$(GunPitchOffset * 360 / 65536)$" deg");
}

// live tuning from the console (~): VRGun 0 0 0 / VRGunPitch 0
exec function VRGun(string S)
{
	GunOffset = ParseVec(S);
	SaveTuning();
}

exec function VRGunPitch(int Degrees)
{
	GunPitchOffset = Degrees * 65536 / 360;
	SaveTuning();
}

// console: VRHeight <uu> - eyes this much above (or below, negative) UT's stock 82 uu eye height; re-measures now
exec function VRHeight(float UU)
{
	EyeHeightBonus = FClamp(UU, -40, 60);
	bMatchGameHeight = true;
	SaveTuning();
	VRRecenter();
	ClientMessage("UT2004VR: eye height "$(82 + EyeHeightBonus)$" uu ("$((82 + EyeHeightBonus) / UUPerMeter)$" m)");
}

// debug: VRTestAim <pitch deg> - set the keyboard/mouse aim pitch (tests the view tilt without a mouse)
exec function VRTestAim(int PitchDeg)
{
	local rotator R;
	R = Rotation;
	R.Pitch = PitchDeg * 65536 / 360;
	SetRotation(R);
}

// console: VRKeyboard - toggle keyboard/mouse mode (saved)
exec function VRKeyboard()
{
	local rotator R;
	bKeyboardMouse = !bKeyboardMouse;
	if ( bKeyboardMouse )
	{
		// start facing where the body faced
		R = Rotation;
		R.Yaw = BodyYaw;
		R.Pitch = 0;
		SetRotation(R);
	}
	// keep the chair's forward: re-capturing it here caught the head looking at the keyboard
	bAnchorValid = false;
	SaveTuning();
	ClientMessage("UT2004VR: keyboard/mouse mode "$bKeyboardMouse);
}

exec function VRSnap(int Degrees)
{
	SnapTurnDegrees = Degrees;
	bSmoothTurn = Degrees <= 0;
	SaveTuning();
}

exec function VRHandMove(bool b)
{
	bHandRelativeMove = b;
	SaveTuning();
}

exec function VRSpeed(float S)
{
	MoveSpeedScale = S;
	SaveTuning();
}

exec function VRScale(float S)
{
	UUPerMeter = S;
	SaveTuning();
}

defaultproperties
{
	UUPerMeter=52.5
	bHandRelativeMove=false
	bGazeHeading=true
	HeadingTurnRate=2.0
	bSteerByGaze=true
	bKeyboardMouse=false
	KBMGunOffset=(X=16,Y=7,Z=-6)
	KBMChestBelowEyes=0.32
	GunLagTime=0.12
	GunLagMax=0.015
	GunLagSmooth=0.15
	RecoilScale=1.0
	RecoilReturn=0.22
	Recoils(0)=(Fire="ZoomSuperShockBeamFire",Back=8,Up=10)
	Recoils(1)=(Fire="SuperShockBeamFire",Back=8,Up=10)
	Recoils(2)=(Fire="ShockBeamFire",Back=7,Up=9)
	Recoils(3)=(Fire="ShockProjFire",Back=5,Up=7)
	Recoils(4)=(Fire="SniperFire",Back=12,Up=15)
	Recoils(5)=(Fire="FlakFire",Back=12,Up=16)
	Recoils(6)=(Fire="FlakAltFire",Back=12,Up=18)
	Recoils(7)=(Fire="RocketMultiFire",Back=14,Up=18)
	Recoils(8)=(Fire="RocketFire",Back=10,Up=12)
	Recoils(9)=(Fire="RedeemerFire",Back=15,Up=18)
	Recoils(10)=(Fire="BioChargedFire",Back=8,Up=10)
	Recoils(11)=(Fire="BioFire",Back=4,Up=6)
	Recoils(12)=(Fire="AssaultGrenade",Back=6,Up=8)
	Recoils(13)=(Fire="AssaultFire",Back=2.5,Up=3.5)
	Recoils(14)=(Fire="MinigunFire",Back=1,Up=1.5)
	Recoils(15)=(Fire="LinkAltFire",Back=2.5,Up=3.5)
	Recoils(16)=(Fire="LinkFire",Back=0.5,Up=0.7)
	Recoils(17)=(Fire="ShieldFire",Back=-10,Up=3)
	Recoils(18)=(Fire="ShieldAltFire",Back=0,Up=0)
	Recoils(19)=(Fire="TransFire",Back=3,Up=5)
	Recoils(20)=(Fire="PainterFire",Back=0,Up=0)
	Recoils(21)=(Fire="ONSAVRiLFire",Back=12,Up=14)
	Recoils(22)=(Fire="ONSGrenadeFire",Back=5,Up=8)
	Recoils(23)=(Fire="ONSMineThrowFire",Back=4,Up=6)
	NeckModelMode=2
	NeckBlendTime=0.3
	NeckForward=0.09
	NeckUp=0.10
	SteerGain=1.5
	SteerDeadzone=8
	SteerMaxDegPerSec=120
	bSmoothTurn=false
	SnapTurnDegrees=45
	SmoothTurnDegPerSec=120
	MoveSpeedScale=0.45
	bTeleport=true
	TeleportSpeed=1100
	TeleportMaxDist=1600
	CrouchHeadMeters=1.1
	bVignette=true
	bVRHud=true
	HudDistance=2.5
	ScoresWidthDeg=40
	bVRMessages=true
	bVRScoreboardOriginal=true
	bVROriginalHud=true
	OriginalHudScale=1.0
	ASTurretFollow=0.15
	bVRClock=true
	VRMessageFontBoost=2
	HudSpread=2.9
	HudTopUp=0.56
	HudBottomUp=-0.56
	HudLower=0.05
	HudSize=0.85
	bMirrorFitHud=true
	MirrorHudMargin=0.1
	bDebugLog=true
	bAutoHeight=true
	bWeapons=true
	GunOffset=(X=0,Y=0,Z=0)
	GunScale=1.0
	bLaser=true
	bVehicleLaser=true
	TurretSpeed=0.6
	GazeSteerFollow=0.3
	VehicleBehindPitch=12
	VehicleBehindScale=1.0
	InstantTurretSpeed=0
	FighterSteer=2000
	RedeemerSteer=2000
	BehindDistance=1.8
	BehindHeight=0.45
	BehindRight=0.35
	bRedeemerRoll=false
	bRedeemerWindow=true
	RedeemerWindowDeg=80
	RedeemerWindowDist=0.6
	bScope=true
	ScopeDiameter=0.10
	ScopeOffset=(X=0.02,Y=0.0,Z=0.07)
	ScopeKBMDiameter=0.21
	ScopeKBMDistance=0.54
	ScopeMinZoom=2.0
	ScopeRes=512
	LaserRange=12000
	LaserDotSize=0.0006
	LaserBrightness=0.45
	LaserWidth=0.6
	LaserFadeIn=0.5
	CurCal=-1
	MirrorEye=-1
	MuzzleForward=4
	PawnClass=Class'UT2004VR.VRPawn'
	StandEyeMeters=1.62
	bMatchGameHeight=true
	bSeatedAutoLevel=true
	AutoLevelSeconds=15
	EyeFOV=100
	EyeOfs(0)=(X=0,Y=-0.032,Z=0)
	EyeOfs(1)=(X=0,Y=0.032,Z=0)
	EyeF(0)=(X=1,Y=0,Z=0)
	EyeF(1)=(X=1,Y=0,Z=0)
	EyeU(0)=(X=0,Y=0,Z=1)
	EyeU(1)=(X=0,Y=0,Z=1)
}
