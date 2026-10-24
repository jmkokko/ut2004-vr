//=============================================================================
// VROnslaughtMap: Onslaught's map tab (the spawn-point map when you die or wait, node teleport) in VR. UT's tab
// draws through PlayerOwner().myHUD as Onslaught's HUD; in VR that is VRHUD, and the game type's own HUD runs beside
// it (VRHUD.Shadow). The map and its hints were blank (Accessed None 'ONSHUD' every frame). For the two functions
// that read it, myHUD is that HUD; UT's own code does the rest.
//=============================================================================
class VROnslaughtMap extends UT2K4Tab_OnslaughtMap;

var HUD SavedHUD;

function bool UseONSHud()
{
	local PlayerController PC;
	PC = PlayerOwner();
	if ( PC == None || VRHUD(PC.myHUD) == None || ONSHUDOnslaught(VRHUD(PC.myHUD).Shadow) == None )
		return false;
	SavedHUD = PC.myHUD;
	PC.myHUD = VRHUD(PC.myHUD).Shadow;
	return true;
}

function RestoreHud()
{
	if ( SavedHUD != None && PlayerOwner() != None )
		PlayerOwner().myHUD = SavedHUD;
	SavedHUD = None;
}

function bool InternalOnPreDraw(Canvas C)
{
	local bool b;
	if ( !UseONSHud() && ONSHUDOnslaught(PlayerOwner().myHUD) == None )
		return false;
	b = Super.InternalOnPreDraw(C);
	RestoreHud();
	return b;
}

function bool DrawMap(Canvas C)
{
	local bool b;
	if ( !UseONSHud() && ONSHUDOnslaught(PlayerOwner().myHUD) == None )
		return false;
	b = Super.DrawMap(C);
	RestoreHud();
	return b;
}
