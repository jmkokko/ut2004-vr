//=============================================================================
// VRLensActor: the zoom lens as a real object in the scene (a flat disc facing +X), so the eyes draw it with true
// perspective: it keeps facing your aim and stays level when you look around, instead of turning with the eye's
// screen. One carries the magnified picture (VRPlayerController.ScopeMat), one slightly larger the dark rim.
//=============================================================================
class VRLensActor extends Actor;

#exec MESH IMPORT MESH=VRLensDisc ANIVFILE=Models\VRLensDisc_a.3d DATAFILE=Models\VRLensDisc_d.3d X=0 Y=0 Z=0 MLOD=0
#exec MESH ORIGIN MESH=VRLensDisc X=0 Y=0 Z=0
#exec MESH SEQUENCE MESH=VRLensDisc SEQ=All STARTFRAME=0 NUMFRAMES=1
#exec MESHMAP NEW MESHMAP=VRLensDisc MESH=VRLensDisc
#exec MESHMAP SCALE MESHMAP=VRLensDisc X=1.0 Y=1.0 Z=1.0
#exec TEXTURE IMPORT NAME=VRLensDefault FILE=Textures\ScopeMask.tga MIPS=OFF ALPHA=1 LODSET=LODSET_Interface
#exec MESHMAP SETTEXTURE MESHMAP=VRLensDisc NUM=0 TEXTURE=VRLensDefault

defaultproperties
{
	DrawType=DT_Mesh
	Mesh=VertMesh'VRLensDisc'
	bUnlit=true
	bHidden=true
	bCollideActors=false
	bBlockActors=false
	bBlockPlayers=false
	bProjTarget=false
	bAcceptsProjectors=false
	bShadowCast=false
	RemoteRole=ROLE_None
	Physics=PHYS_None
	bMovable=true
	bAlwaysTick=true
}
