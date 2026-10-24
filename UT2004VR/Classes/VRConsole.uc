//=============================================================================
// VRConsole: UT's console with two VR jobs (System/UT2004.ini [Engine.Engine] Console=UT2004VR.VRConsole).
//  - Every game UT's menus start (Instant Action, Host Game: "start <url>") gets ?Mutator=UT2004VR.VRMutator,
//    so whatever gametype, map and rules you pick, you play it in VR.
//  - Where no VRPlayerController runs (the main menus, before any game), it runs the headset menu itself: a
//    VRLink to the proxy, which then draws the headset view on its own (a dark room with the menu panel), and
//    VRMenu for the pointer and the trigger clicks.
//=============================================================================
class VRConsole extends ExtendedConsole
	config(UT2004VR);

var VRConsoleLink Link;
var VRMenu Menu;
var bool bBtnFire;
var float LastPacketTime;
var config string MenuTestExec;   // debug: commands run in the main menus, "a|b|c", one every ~90 ticks
var string MenuTestNext;
var int MenuTestFrames;
var bool bMenuTestStarted;
var LevelInfo LastLevel;
var string ReloadedURL;           // the level being reloaded with the VR mutator (no second try until VR comes up)

function DelayedConsoleCommand(string Command)
{
	Super.DelayedConsoleCommand(WithVRMutator(Command));
}

static function string WithVRMutator(string Command)
{
	local string Verb, URL;
	local int i;
	i = InStr(Command, " ");
	if ( i < 0 )
		return Command;
	Verb = Left(Command, i);
	URL = Mid(Command, i + 1);
	if ( !(Verb ~= "start" || Verb ~= "open" || Verb ~= "travel") || InStr(Caps(URL), "UT2004VR.VRMUTATOR") >= 0 )
		return Command;
	// a map URL (not a server address or a demo)
	if ( InStr(URL, "?") < 0 && InStr(URL, ".") >= 0 )
		return Command;
	i = InStr(Caps(URL), "?MUTATOR=");
	if ( i >= 0 )
		URL = Left(URL, i + 9) $ "UT2004VR.VRMutator," $ Mid(URL, i + 9);
	else
		URL = URL $ "?Mutator=UT2004VR.VRMutator";
	Log("UT2004VR: console "$Verb$" "$URL, 'UT2004VR');
	return Verb $ " " $ URL;
}

// A local game running without VR: started by a path that doesn't go through this console (Single Player's
// tutorials and ladder use PlayerOwner().ConsoleCommand("START ..."), straight into the engine). Load the same URL
// again with the VR mutator, once. Not for the menus (Entry, plain GameInfo), the intro, or network clients (the
// server decides the player class there; no Level.Game on a client).
function bool WillReloadWithVR(PlayerController PC)
{
	local string URL;
	if ( PC.Level.Game == None || PC.Level.Game.Class == class'GameInfo' || CinematicGame(PC.Level.Game) != None
		|| PC.Level.NetMode == NM_Client )
		return false;
	URL = PC.Level.GetLocalURL();
	return URL != "" && InStr(Caps(URL), "UT2004VR.VRMUTATOR") < 0 && URL != ReloadedURL;
}

function bool ReloadWithVR(PlayerController PC)
{
	local string URL, Opt, Out;
	local array<string> Parts;
	local int k;
	local bool bSpecOpt;
	if ( !WillReloadWithVR(PC) || PC.Level.TimeSeconds < 0.5 )
		return false;
	URL = PC.Level.GetLocalURL();
	ReloadedURL = URL;   // once per URL: if the reload doesn't bring VR, leave it
	// the map and options only (the local URL starts with the protocol and host on some builds)
	if ( InStr(URL, "/") >= 0 )
		URL = Mid(URL, InStr(URL, "/") + 1);
	// keep the player's own options as the game was started with them: Single Player plays as its profile (its
	// name, character and team, "NoSaveDefPlayer"), and without them the engine filled in [DefaultPlayer] - the
	// multiplayer name, character and SpectatorOnly=1, so the ladder match started with you as a spectator. Only
	// an option with a space is left out (a character called "Combine Charger" would cut the console command short).
	Split(URL, "?", Parts);
	Out = Parts[0];
	for ( k = 1; k < Parts.Length; k++ )
	{
		Opt = Caps(Left(Parts[k], InStr(Parts[k] $ "=", "=")));
		if ( Opt == "SPECTATORONLY" )
			bSpecOpt = true;
		if ( InStr(Parts[k], " ") >= 0 )
			continue;
		Out = Out $ "?" $ Parts[k];
	}
	// started without a spectator option: a player, whatever [DefaultPlayer] says
	if ( !bSpecOpt )
		Out = Out $ "?SpectatorOnly=0";
	URL = Mid(WithVRMutator("open " $ Out), 5);
	Log("UT2004VR: "$PC.Level.Game.Class$" started without VR: reloading "$URL, 'UT2004VR');
	PC.ConsoleCommand("open " $ URL);
	return true;
}

// a new level: free the proxy port for the VR controller of the game that is starting
event NotifyLevelChange()
{
	if ( Link != None && !Link.bDeleteMe )
		Link.Destroy();
	Link = None;
	Super.NotifyLevelChange();
}

event Tick(float Delta)
{
	local PlayerController PC;
	local GUIController G;

	Super.Tick(Delta);
	PC = ViewportOwner.Actor;
	if ( PC != None && PC.Level != LastLevel )
	{
		LastLevel = PC.Level;
		Log("UT2004VR: level "$PC.Level$" ("$PC.Level.Title$") game "$PC.Level.Game.Class$" controller "$PC.Class, 'UT2004VR');
	}
	if ( PC != None )
		TickMenuTest();
	if ( PC == None || VRPlayerController(PC) != None )
	{
		// a VR game runs: the controller has the link and the menu. The reload guard only has to last until VR
		// is up (the same ladder match played again has the same URL and needs its reload too)
		if ( VRPlayerController(PC) != None )
			ReloadedURL = "";
		if ( Link != None && !Link.bDeleteMe )
			Link.Destroy();
		Link = None;
		return;
	}
	if ( ReloadWithVR(PC) )
		return;
	if ( Link == None || Link.bDeleteMe )
	{
		Link = PC.Spawn(class'VRConsoleLink');
		if ( Link == None )
			return;
		Link.Con = self;
	}
	if ( Menu == None )
		Menu = new class'VRMenu';
	Link.Drain();
	G = GUIController(ViewportOwner.GUIController);
	Menu.Update(Link, G, class'VRTuning'.default.bKeyboardMouse, bBtnFire, PC.Level.TimeSeconds, ViewMode(PC));
}

// the main menus (UT's menu level runs a plain GameInfo): the dark room; a network game or a local one without VR:
// the game window on a big screen
function int ViewMode(PlayerController PC)
{
	// a local game started without VR that we're about to load again with it (Single Player's ladder): the dark
	// room, not its flat window for the moment until the reload (that was a 2D flicker)
	if ( WillReloadWithVR(PC) )
		return 1;
	if ( PC.Level.NetMode == NM_Client || (PC.Level.Game != None && PC.Level.Game.Class != class'GameInfo') )
		return 2;
	return 1;
}

// keyboard/mouse <-> controller mode, here too (the main menus have no VR controller to run it)
exec function VRKeyboard()
{
	class'VRTuning'.default.bKeyboardMouse = !class'VRTuning'.default.bKeyboardMouse;
	class'VRTuning'.default.bSaved = true;
	class'VRTuning'.static.StaticSaveConfig();
	if ( VRPlayerController(ViewportOwner.Actor) != None )
		VRPlayerController(ViewportOwner.Actor).bKeyboardMouse = class'VRTuning'.default.bKeyboardMouse;
	Message("UT2004VR: keyboard/mouse mode "$class'VRTuning'.default.bKeyboardMouse, 6.0);
	Log("UT2004VR: keyboard/mouse mode "$class'VRTuning'.default.bKeyboardMouse, 'UT2004VR');
}

// debug: start a game the way UT's menus do (through DelayedConsoleCommand, so with the VR mutator)
exec function VRStart(string URL)
{
	DelayedConsoleCommand("start " $ URL);
}

// debug: open a menu page by class, e.g. VROpenMenu GUI2K4.UT2K4QuitPage (what Esc does in the main menus)
exec function VROpenMenu(string MenuClass)
{
	GUIController(ViewportOwner.GUIController).OpenMenu(MenuClass);
}

exec function VRMenuDump()
{
	class'VRMenu'.static.Dump(GUIController(ViewportOwner.GUIController));
}

exec function VRMenuClick(string UV)
{
	local array<string> P;
	if ( Menu == None )
		Menu = new class'VRMenu';
	if ( Split(UV, " ", P) >= 2 )
		Menu.Click(GUIController(ViewportOwner.GUIController), float(P[0]), float(P[1]));
}

function TickMenuTest()
{
	local int i;
	local string Cmd;
	if ( !bMenuTestStarted && MenuTestExec != "" && ViewportOwner.Actor.Level.TimeSeconds > 5 )
	{
		bMenuTestStarted = true;
		MenuTestNext = MenuTestExec;
		MenuTestFrames = 1;
	}
	if ( MenuTestNext == "" || --MenuTestFrames > 0 )
		return;
	i = InStr(MenuTestNext, "|");
	if ( i < 0 ) { Cmd = MenuTestNext; MenuTestNext = ""; }
	else { Cmd = Left(MenuTestNext, i); MenuTestNext = Mid(MenuTestNext, i + 1); }
	MenuTestFrames = 90;
	Log("UT2004VR: menu test step '"$Cmd$"'", 'UT2004VR');
	ViewportOwner.Actor.ConsoleCommand(Cmd);
}

// packets from the proxy while no VR game runs: the trigger and the pointer
function VRPacket(string Text)
{
	local array<string> P;
	local int n;
	n = Split(Text, " ", P);
	if ( n < 1 )
		return;
	LastPacketTime = ViewportOwner.Actor.Level.TimeSeconds;
	switch ( P[0] )
	{
	case "I":
		if ( n >= 12 )
			bBtnFire = P[8] == "1";
		break;
	case "U":
		if ( n >= 3 && Menu != None )
			Menu.Pointer(GUIController(ViewportOwner.GUIController), float(P[1]), float(P[2]), class'VRTuning'.default.bKeyboardMouse);
		break;
	}
}

defaultproperties
{
}
