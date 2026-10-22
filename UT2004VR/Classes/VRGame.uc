//=============================================================================
// VRGame: a calm deathmatch for walking UT2004 maps in VR. No bots, no limits.
// Launch:  UT2004.exe DM-Rankin?Game=UT2004VR.VRGame
//=============================================================================
class VRGame extends xDeathMatch
	config(UT2004VR);

var config int VRNumBots;         // bots to fight (URL ?NumBots=N overrides)
var config int BotSkill;         // UT difficulty 0 (Novice) .. 7 (Godlike); URL ?Difficulty=N overrides
var config string BotNames;      // scoreboard names: "" = UT's roster names, or your own names, comma-separated
                                 // (used in order, repeating: Alpha, Bravo, Alpha2...)
var config string ExtraWeapon;   // e.g. XWeapons.ShockRifle: also given at spawn (testing, or a favourite gun)

event InitGame( string Options, out string Error )
{
	// bots: DeathMatch reads them from the URL, so add our defaults unless the URL already says
	if ( !HasOption(Options, "NumBots") )
		Options = Options $ "?NumBots=" $ VRNumBots;
	if ( !HasOption(Options, "Difficulty") )
		Options = Options $ "?Difficulty=" $ BotSkill;
	Super.InitGame(Options, Error);
	AddMutator("UT2004VR.VRMutator");   // bot characters, names, glow (the console adds it to other gametypes)
	Log("UT2004VR: InitGame options="$Options$" -> InitialBots="$InitialBots$" MinPlayers="$MinPlayers$" difficulty="$GameDifficulty, 'UT2004VR');
	TimeLimit = 0;
	GoalScore = 0;
	// offline: "Press FIRE to start!" and the countdown, as in the original; online the server starts at once
	if ( Level.NetMode != NM_Standalone )
		bQuickStart = true;
}

// travel-only mode (VRPlayerController bWeapons=False): no guns
function AddDefaultInventory( pawn PlayerPawn )
{
	if ( class'VRPlayerController'.default.bWeapons )
	{
		Super.AddDefaultInventory(PlayerPawn);
		if ( ExtraWeapon ~= "all" )
		{
			PlayerPawn.GiveWeapon("XWeapons.ShockRifle");
			PlayerPawn.GiveWeapon("XWeapons.LinkGun");
			PlayerPawn.GiveWeapon("XWeapons.FlakCannon");
			PlayerPawn.GiveWeapon("XWeapons.RocketLauncher");
			PlayerPawn.GiveWeapon("XWeapons.Minigun");
			PlayerPawn.GiveWeapon("XWeapons.BioRifle");
			PlayerPawn.GiveWeapon("XWeapons.SniperRifle");
			PlayerPawn.GiveWeapon("XWeapons.Redeemer");
			PlayerPawn.GiveWeapon("XWeapons.Painter");
			PlayerPawn.GiveWeapon("UTClassic.ClassicSniperRifle");
		}
		else if ( ExtraWeapon != "" )
		{
			PlayerPawn.GiveWeapon(ExtraWeapon);
			if ( PlayerPawn.Controller != None )
				PlayerPawn.Controller.SwitchToBestWeapon();
		}
	}
	else
		SetPlayerDefaults(PlayerPawn);
}

function bool PickupQuery( Pawn Other, Pickup item )
{
	if ( !class'VRPlayerController'.default.bWeapons
		&& (item.IsA('WeaponPickup') || item.IsA('Ammo') || item.IsA('UTAmmoPickup')) )
		return false;
	return Super.PickupQuery(Other, item);
}

function StartMatch()
{
	Log("UT2004VR: StartMatch InitialBots="$InitialBots$" NumBots="$NumBots, 'UT2004VR');
	Super.StartMatch();
	Log("UT2004VR: after StartMatch NumBots="$NumBots$" RemainingBots="$RemainingBots, 'UT2004VR');
}

defaultproperties
{
	GameName="VR Travel"
	Description="Walk UT2004 maps in VR with Half-Life: Alyx style locomotion."
	Acronym="VR"
	PlayerControllerClassName="UT2004VR.VRPlayerController"
	HUDType="UT2004VR.VRHUD"
	DefaultPlayerClassName="UT2004VR.VRPawn"
	bAllowBehindView=false
	VRNumBots=4
	BotSkill=2
	bWeaponStay=true
	MinPlayers=0
	bPlayersMustBeReady=false
}
