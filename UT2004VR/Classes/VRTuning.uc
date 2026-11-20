//=============================================================================
// VRTuning: the values the console commands change (VRGun, VRGunScale, VRGunPitch, VRSnap,
// VRHandMove, VRSpeed, VRScale), saved in their own [UT2004VR.VRTuning] section.
// (SaveConfig on the controller would also dump every inherited PlayerController setting.)
//=============================================================================
class VRTuning extends Object
	config(UT2004VR);

// per-weapon handle adjustment: moves the gun in your hand (gun axes: forward, right, up; uu)
struct GripOfs
{
	var string Gun;      // weapon class name, e.g. ShockRifle
	var vector Offset;
};

// per-vehicle seat in VR: moves your eyes from the vehicle's own driver camera (vehicle axes: forward, right, up;
// uu), and whether to draw the vehicle around you (UT hides some in first person: Raptor, Manta; the Goliath's
// hull and turret can fill the view)
struct VehSeat
{
	var string Vehicle;  // vehicle class name, e.g. ONSAttackCraft
	var vector Offset;
	var bool   bShowMesh;  // draw it (VRSeatMesh)
	var bool   bHideMesh;  // hide it and its guns; neither: UT's own choice
};

// per-weapon scope lens in controller mode (VRScope): its centre from the gun's handle (gun axes: forward, right,
// up; m) and its diameter (m; 0 = ScopeDiameter)
struct ScopeOfs
{
	var string Gun;
	var vector Offset;
	var float  Diameter;
};

var config bool   bSaved;
var config vector GunOffset;
var config float  GunScale;
var config int    GunPitchOffset;
var config int    SnapTurnDegrees;
var config bool   bSmoothTurn;
var config bool   bHandRelativeMove;
var config float  MoveSpeedScale;
var config float  UUPerMeter;
var config float  EyeHeightBonus;
var config bool   bKeyboardMouse;
var config bool   bMatchGameHeight;
var config array<string> FlipGuns;
var config array<GripOfs> KBMGrips;   // the same per weapon for keyboard/mouse mode (gun in front of the chest)
var config array<VehSeat> VehSeats;
var config array<ScopeOfs> Scopes;
var config array<GripOfs> Grips;   // third-person models that are modelled upside down

defaultproperties
{
	// the tuning from the author's play-testing (HP Reverb-style WMR headset, seated): per-weapon grips for
	// controller and keyboard modes, scope lenses, vehicle seats. A player's own VRGrip / VRScope / VRSeat
	// changes are saved over these in UT2004VR.ini. Controller mode by default (VRKeyboard switches).
	bSaved=True
	GunOffset=(X=0,Y=0,Z=0)
	GunScale=1
	GunPitchOffset=-1820
	SnapTurnDegrees=45
	bSmoothTurn=False
	bHandRelativeMove=False
	MoveSpeedScale=1
	UUPerMeter=52.5
	EyeHeightBonus=0
	bMatchGameHeight=True
	bKeyboardMouse=False
	KBMGrips(0)=(Gun="ShieldGun",Offset=(X=-10,Y=-1,Z=1))
	KBMGrips(1)=(Gun="AssaultRifle",Offset=(X=-20,Y=4,Z=0))
	KBMGrips(2)=(Gun="BioRifle",Offset=(X=-14,Y=-1,Z=2))
	KBMGrips(3)=(Gun="ShockRifle",Offset=(X=-12,Y=4,Z=-10))
	KBMGrips(4)=(Gun="LinkGun",Offset=(X=0,Y=4,Z=-5))
	KBMGrips(5)=(Gun="Minigun",Offset=(X=-20,Y=0,Z=0))
	KBMGrips(6)=(Gun="FlakCannon",Offset=(X=-20,Y=-1,Z=2))
	KBMGrips(7)=(Gun="RocketLauncher",Offset=(X=-12,Y=-1,Z=-5))
	KBMGrips(8)=(Gun="SniperRifle",Offset=(X=-14,Y=0,Z=2))
	KBMGrips(9)=(Gun="ClassicSniperRifle",Offset=(X=-20,Y=0,Z=9))
	KBMGrips(10)=(Gun="Redeemer",Offset=(X=-30,Y=-1,Z=-1))
	KBMGrips(11)=(Gun="Translauncher",Offset=(X=-6,Y=0,Z=4))
	KBMGrips(12)=(Gun="BallLauncher",Offset=(X=-10,Y=0,Z=0))
	KBMGrips(13)=(Gun="Painter",Offset=(X=-20,Y=0,Z=2))
	KBMGrips(14)=(Gun="ONSAVRiL",Offset=(X=20,Y=-16,Z=2))
	KBMGrips(15)=(Gun="ONSGrenadeLauncher",Offset=(X=-8,Y=-2,Z=5))
	KBMGrips(16)=(Gun="ONSMineLayer",Offset=(X=-12,Y=0,Z=0))
	KBMGrips(17)=(Gun="ONSPainter",Offset=(X=-4,Y=-2,Z=2))
	VehSeats(0)=(Vehicle="ONSAttackCraft",Offset=(X=0,Y=0,Z=0),bShowMesh=True,bHideMesh=False)
	VehSeats(1)=(Vehicle="ONSHoverBike",Offset=(X=0,Y=0,Z=0),bShowMesh=True,bHideMesh=False)
	VehSeats(2)=(Vehicle="ONSHoverTank",Offset=(X=40,Y=0,Z=-60),bShowMesh=False,bHideMesh=False)
	VehSeats(3)=(Vehicle="ONSRV",Offset=(X=-10,Y=0,Z=0),bShowMesh=False,bHideMesh=False)
	VehSeats(4)=(Vehicle="ONSPRVRearGunPawn",Offset=(X=0,Y=0,Z=80),bShowMesh=False,bHideMesh=False)
	VehSeats(5)=(Vehicle="ONSPRVSideGunPawn",Offset=(X=-10,Y=0,Z=0),bShowMesh=False,bHideMesh=False)
	VehSeats(6)=(Vehicle="ONSPRV",Offset=(X=-20,Y=10,Z=0),bShowMesh=False,bHideMesh=False)
	VehSeats(7)=(Vehicle="ONSDualAttackCraft",Offset=(X=90,Y=0,Z=176),bShowMesh=False,bHideMesh=False)
	VehSeats(8)=(Vehicle="ONSDualACGatlingGunPawn",Offset=(X=-20,Y=0,Z=-40),bShowMesh=False,bHideMesh=False)
	VehSeats(9)=(Vehicle="ASVehicle_SpaceFighter_Human",Offset=(X=0,Y=0,Z=10),bShowMesh=False,bHideMesh=False)
	VehSeats(10)=(Vehicle="ONSManualGunPawn",Offset=(X=23,Y=0,Z=60),bShowMesh=False,bHideMesh=False)
	VehSeats(11)=(Vehicle="ASTurret_Minigun",Offset=(X=20,Y=0,Z=0),bShowMesh=False,bHideMesh=False)
	VehSeats(12)=(Vehicle="ASVehicle_SpaceFighter_Skaarj",Offset=(X=30,Y=0,Z=10),bShowMesh=False,bHideMesh=False)
	VehSeats(13)=(Vehicle="ONSShockTank",Offset=(X=0,Y=0,Z=-30),bShowMesh=False,bHideMesh=False)
	VehSeats(14)=(Vehicle="ASTurret_BallTurret",Offset=(X=50,Y=0,Z=0),bShowMesh=False,bHideMesh=False)
	VehSeats(15)=(Vehicle="ASTurret_LinkTurret",Offset=(X=70,Y=0,Z=65),bShowMesh=False,bHideMesh=False)
	VehSeats(16)=(Vehicle="ONSTankSecondaryTurretPawn_IonPlasma",Offset=(X=14,Y=0,Z=20),bShowMesh=False,bHideMesh=False)
	Scopes(0)=(Gun="SniperRifle",Offset=(X=0.04,Y=-0.02,Z=0.19),Diameter=0)
	Scopes(1)=(Gun="ClassicSniperRifle",Offset=(X=0.24,Y=-0.01,Z=0.07),Diameter=0)
	Scopes(2)=(Gun="ZoomSuperShockRifle",Offset=(X=0.06,Y=-0.095,Z=0.35),Diameter=0)
	Grips(0)=(Gun="ShieldGun",Offset=(X=-2,Y=0,Z=0))
	Grips(1)=(Gun="AssaultRifle",Offset=(X=-24,Y=5,Z=0))
	Grips(2)=(Gun="BioRifle",Offset=(X=-4,Y=0,Z=0))
	Grips(3)=(Gun="ShockRifle",Offset=(X=-6,Y=6,Z=-10))
	Grips(4)=(Gun="LinkGun",Offset=(X=12,Y=6,Z=-7))
	Grips(5)=(Gun="Minigun",Offset=(X=-4,Y=2,Z=0))
	Grips(6)=(Gun="FlakCannon",Offset=(X=-3,Y=1,Z=0))
	Grips(7)=(Gun="RocketLauncher",Offset=(X=-4,Y=1,Z=-1))
	Grips(8)=(Gun="SniperRifle",Offset=(X=-4,Y=2,Z=-1))
	Grips(9)=(Gun="ClassicSniperRifle",Offset=(X=-20,Y=0,Z=6))
	Grips(10)=(Gun="Redeemer",Offset=(X=-22,Y=0,Z=-1))
	Grips(11)=(Gun="Translauncher",Offset=(X=-2,Y=1,Z=0))
	Grips(12)=(Gun="BallLauncher",Offset=(X=-1,Y=1,Z=0))
	Grips(13)=(Gun="Painter",Offset=(X=-3,Y=0,Z=1))
	Grips(14)=(Gun="ONSAVRiL",Offset=(X=10,Y=-10,Z=0))
	Grips(15)=(Gun="ONSGrenadeLauncher",Offset=(X=0,Y=0,Z=3))
	Grips(16)=(Gun="ONSMineLayer",Offset=(X=-1,Y=1,Z=-1))
	Grips(17)=(Gun="ONSPainter",Offset=(X=4,Y=-3,Z=2))
}
