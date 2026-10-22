//=============================================================================
// VRMutator: VR in any gametype. VRConsole adds it to every game UT's menus start (Instant Action, Host Game);
// VRGame adds it too. It makes the local player a VRPlayerController (head-tracked eyes, hands, VR HUD, menus),
// skips "press fire to start", and names the bots (BotNames under [UT2004VR.VRGame]).
//=============================================================================
class VRMutator extends Mutator;

var int BotNameIndex;
var float ReadyAt;               // when the local player was marked ready (logged when the match starts)
var array<Controller> Named;     // bots that already got their name

function PostBeginPlay()
{
	Super.PostBeginPlay();
	// before anyone logs in: GameInfo.Login spawns PlayerControllerClass
	Level.Game.PlayerControllerClass = class'VRPlayerController';
	Level.Game.PlayerControllerClassName = "UT2004VR.VRPlayerController";
	// nobody can "press fire to start" with a headset on: offline you are marked ready (Tick), so UT still plays its
	// 3-2-1 countdown (and Assault its intro, which needs quickstart off); online the server starts at once
	if ( DeathMatch(Level.Game) != None && Level.NetMode != NM_Standalone )
		DeathMatch(Level.Game).bQuickStart = true;
	Log("UT2004VR: VR mutator in "$Level.Game.Class, 'UT2004VR');
}

// offline, while the match waits for players to be ready: you are (as if you had pressed fire), so the countdown runs
function Tick(float DeltaTime)
{
	local Controller C;
	local PlayerController PC;

	if ( Level.NetMode != NM_Standalone )
		return;
	if ( !Level.Game.IsInState('PendingMatch') )
	{
		if ( ReadyAt > 0 )
		{
			Log("UT2004VR: match started "$(Level.TimeSeconds - ReadyAt)$" s after you were ready", 'UT2004VR');
			ReadyAt = 0;
		}
		return;
	}
	for ( C = Level.ControllerList; C != None; C = C.NextController )
	{
		PC = PlayerController(C);
		if ( PC != None && PC.PlayerReplicationInfo != None && PC.PlayerReplicationInfo.bWaitingPlayer
			&& !PC.PlayerReplicationInfo.bReadyToPlay && !PC.PlayerReplicationInfo.bOnlySpectator )
		{
			PC.PlayerReplicationInfo.bReadyToPlay = true;
			ReadyAt = Level.TimeSeconds;
			Log("UT2004VR: "$PC.PlayerReplicationInfo.PlayerName$" ready: the match countdown runs", 'UT2004VR');
		}
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
