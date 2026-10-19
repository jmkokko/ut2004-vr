//=============================================================================
// VRMutator: VR in any gametype. VRConsole adds it to every game UT's menus start (Instant Action, Host Game);
// VRGame adds it too. It makes the local player a VRPlayerController (head-tracked eyes, hands, VR HUD, menus),
// skips "press fire to start", and names the bots (BotNames under [UT2004VR.VRGame]).
//=============================================================================
class VRMutator extends Mutator;

var int BotNameIndex;
var bool bAssaultIntro;          // Assault: quickstart is off until the local player is in (its intro plays)
var array<Controller> Named;     // bots that already got their name

function PostBeginPlay()
{
	Super.PostBeginPlay();
	// before anyone logs in: GameInfo.Login spawns PlayerControllerClass
	Level.Game.PlayerControllerClass = class'VRPlayerController';
	Level.Game.PlayerControllerClassName = "UT2004VR.VRPlayerController";
	if ( DeathMatch(Level.Game) != None )
		DeathMatch(Level.Game).bQuickStart = true;   // nobody can "press fire to start" with a headset on
	// Assault plays its Matinee intro (the objective briefing) only for a player who logs in without quickstart:
	// off until you are in, then on again, so the match starts by itself once the intro ends (or at once without one)
	if ( ASGameInfo(Level.Game) != None && Level.NetMode == NM_Standalone )
	{
		ASGameInfo(Level.Game).bQuickStart = false;
		bAssaultIntro = true;
	}
	Log("UT2004VR: VR mutator in "$Level.Game.Class, 'UT2004VR');
}

function Tick(float DeltaTime)
{
	local PlayerController PC;

	if ( !bAssaultIntro )
		return;
	PC = Level.GetLocalPlayerController();
	if ( PC == None || PC.PlayerReplicationInfo == None )
		return;
	bAssaultIntro = false;
	ASGameInfo(Level.Game).bQuickStart = true;
	if ( Level.Game.IsInState('SPIntroCinematic') )
		Log("UT2004VR: Assault intro playing", 'UT2004VR');
	else if ( Level.Game.IsInState('PendingMatch') )
	{
		Log("UT2004VR: no Assault intro: starting the match", 'UT2004VR');
		Level.Game.StartMatch();
	}
}

function ModifyPlayer(Pawn Other)
{
	local xBot B;
	local int i;
	local bool bDone;

	B = xBot(Other.Controller);
	if ( B != None )
	{
		for ( i = 0; i < Named.Length; i++ )
			if ( Named[i] == B )
				bDone = true;
		if ( !bDone )
		{
			Named[Named.Length] = B;
			NameBot(B);
		}
	}
	Super.ModifyPlayer(Other);
}

// BotNames: "" keeps UT's roster names, else a comma-separated list (used in order, repeating)
function NameBot(Bot B)
{
	local array<string> L;
	local string N, Want;
	Want = class'VRGame'.default.BotNames;
	if ( Want == "" )
		return;
	Split(Want, ",", L);
	if ( L.Length == 0 )
		return;
	N = L[BotNameIndex % L.Length];
	BotNameIndex++;
	ReplaceText(N, " ", "");
	N = UniqueBotName(B, N);
	Level.Game.ChangeName(B, N, false);
	Log("UT2004VR: bot named "$B.PlayerReplicationInfo.PlayerName, 'UT2004VR');
}

// "Alpha", then "Alpha2", "Alpha3"... (UT's ChangeName would swap a taken name for a random backup name)
function string UniqueBotName(Controller Me, string N)
{
	local Controller C;
	local int k;
	local string T;
	local bool bTaken;
	for ( k = 1; k < 100; k++ )
	{
		if ( k == 1 )
			T = N;
		else
			T = N $ k;
		bTaken = false;
		for ( C = Level.ControllerList; C != None; C = C.NextController )
			if ( C != Me && C.PlayerReplicationInfo != None && C.PlayerReplicationInfo.PlayerName ~= T )
				bTaken = true;
		if ( !bTaken )
			return T;
	}
	return N;
}

defaultproperties
{
	GroupName="UT2004VR"
	FriendlyName="UT2004 VR"
	Description="Play in VR: head-tracked view, guns in your hands, VR HUD and menus (needs the UT2004VR d3d9.dll and SteamVR)."
}
