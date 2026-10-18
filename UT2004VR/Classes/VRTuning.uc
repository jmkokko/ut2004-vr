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
var config array<GripOfs> Grips;   // third-person models that are modelled upside down

defaultproperties
{
	VehSeats(0)=(Vehicle="ONSAttackCraft",Offset=(X=0,Y=0,Z=0),bShowMesh=true)
	VehSeats(1)=(Vehicle="ONSHoverBike",Offset=(X=0,Y=0,Z=0),bShowMesh=true)
}
