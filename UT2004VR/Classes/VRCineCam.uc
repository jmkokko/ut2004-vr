//=============================================================================
// VRCineCam: an invisible marker kept at a cinematic's camera, passed to DrawPortal as the eyes' camera actor:
// UT renders a portal from that actor's zone, so it has to be where the camera is (the controller isn't).
//=============================================================================
class VRCineCam extends Actor;

defaultproperties
{
	bHidden=true
	bCollideActors=false
	bCollideWorld=false
	bBlockActors=false
	bBlockPlayers=false
	RemoteRole=ROLE_None
	DrawType=DT_None
}
