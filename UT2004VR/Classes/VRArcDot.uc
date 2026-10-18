//=============================================================================
// VRArcDot: one glowing dot of the teleport arc (debug lines do not render
// inside Canvas.DrawPortal views, sprites do).
//=============================================================================
class VRArcDot extends Actor;

defaultproperties
{
	DrawType=DT_Sprite
	Texture=Texture'EpicParticles.Flares.SoftFlare'
	Style=STY_Additive
	DrawScale=0.06
	bUnlit=true
	bHidden=true
	bCollideActors=false
	bCollideWorld=false
	bBlockActors=false
	bBlockPlayers=false
	Physics=PHYS_None
	RemoteRole=ROLE_None
	bAlwaysRelevant=false
}
