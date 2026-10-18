//=============================================================================
// VRLink: receives head/hand pose and controller input from the d3d9 proxy
// (UT2004VR d3d9.dll) as short text datagrams on 127.0.0.1:Port.
//
// Packets (one per datagram, space separated, Unreal axes, uu = meters * scale on our side):
//   H seq px py pz fx fy fz ux uy uz          head pose in playspace (meters, floor = 0)
//   L ok px py pz fx fy fz ux uy uz           left hand aim pose  (ok = 0/1)
//   R ok px py pz fx fy fz ux uy uz           right hand aim pose
//   I mx my tx ty jump crouch menu grabL grabR trigL trigR
//   E eye ox oy oz fx fy fz ux uy uz          eye-to-head transform (eye 0 = left)
//   C fov eyeW eyeH                           integer horizontal FOV per eye portal, eye size in px
//=============================================================================
class VRLink extends UdpLink;

var config int VRPort;
var VRPlayerController PC;
var VRConsole Con;        // the main menus (no VR controller): VRConsole drives the headset menu
var int Packets;
var bool bBound;
var int BindTries;
var int MyPort;
var int PortSeq;          // (class default: the next port offset, kept across levels)
var float NextAnnounce;
var int AnnounceTicks;
var IpAddr ProxyAddr;   // the d3d9 proxy listens on VRPort + 1 for game -> proxy messages

function PostBeginPlay()
{
	Super.PostBeginPlay();
	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Manual;   // RMODE_Event fell behind: it did not deliver every datagram each tick
	StringToIpAddr("127.0.0.1", ProxyAddr);
	ProxyAddr.Port = 7791;   // the proxy listens here for game -> proxy messages
	TryBind();
}

// Every link gets a port of its own (7800 + a counter that outlives levels) and announces it to the proxy ("N"),
// which sends only to the ports announced in the last 2 s. A shared fixed port didn't work: links of unloaded
// levels (the intro's, the menus') keep their sockets, UdpLink shares ports, and Windows then delivered the
// datagrams to a dead socket - the game got no packets and the headset showed a frozen view.
function TryBind()
{
	local int Want;
	Want = 7800 + (class'VRLink'.default.PortSeq % 150);
	class'VRLink'.default.PortSeq++;
	MyPort = BindPort(Want, true);
	if ( MyPort == 0 )
	{
		if ( BindTries++ == 0 )
			Log("UT2004VR: could not bind a UDP port near "$Want$" yet, retrying", 'UT2004VR');
		return;
	}
	bBound = true;
	Log("UT2004VR: listening for poses on UDP "$MyPort$" ("$Class.Name$")", 'UT2004VR');
	Announce();
}

function Announce()
{
	NextAnnounce = Level.TimeSeconds + 0.5;
	SendText(ProxyAddr, "N " $ MyPort);
}

event Tick(float DeltaTime)
{
	Super.Tick(DeltaTime);
	if ( !bBound && BindTries < 600 )
		TryBind();
	// (paused, Level.TimeSeconds stands still: announce by real ticks too)
	if ( bBound && (Level.TimeSeconds > NextAnnounce || --AnnounceTicks <= 0) )
	{
		AnnounceTicks = 45;
		Announce();
	}
	if ( PC != None && Level.Pauser != None )
		PC.PausedVRTick();
}

function ToProxy(string Msg)
{
	SendText(ProxyAddr, Msg);
}

// read every datagram waiting on the socket; called by the controller before it moves and renders
function Drain()
{
	local IpAddr Addr;
	local string Text;
	local int i, n;

	for ( n = 0; n < 256; n++ )
	{
		if ( ReadText(Addr, Text) <= 0 )
			break;
		// ReadText leaves leftovers of longer earlier datagrams after the text: cut at the " ;" terminator
		i = InStr(Text, " ;");
		if ( i < 0 )
			continue;
		Packets++;
		if ( PC != None )
			PC.VRPacket(Left(Text, i));
		else if ( Con != None )
			Con.VRPacket(Left(Text, i));
	}
}

defaultproperties
{
	VRPort=7790
	bAlwaysTick=true
}
