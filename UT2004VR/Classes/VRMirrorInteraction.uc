//=============================================================================
// VRMirrorInteraction: inserted at index 0 of the viewport's interactions, so its PostRender runs after
// everything else (InteractionMaster walks the array backwards). It bumps the eye textures' revision and
// draws them as 1x1 tiles, which makes the engine render both eyes. D3D9Drv doesn't restore the backbuffer
// after rendering a ScriptedTexture, so this has to be the very last drawing of the frame; the console and
// menus are then drawn on the window first (over the mirror backdrop the HUD drew).
//=============================================================================
class VRMirrorInteraction extends Interaction;

var VRPlayerController PC;
var int Frames;

function PostRender(Canvas C)
{
	// interactions outlive the level: once the viewport has a new controller (the startup intro's VR controller
	// after the main menus came up), let go of the old one, which still looks active (it kept sending "M 0", and
	// the headset flipped between the menus and the intro's eyes)
	if ( PC != None && (ViewportOwner == None || ViewportOwner.Actor != PC) )
		PC = None;
	if ( PC == None || PC.bDeleteMe || PC.EyeTex[0] == None || PC.EyeTex[1] == None || !PC.VRActive() )
		return;
	PC.EyeTex[0].Revision++;
	PC.EyeTex[1].Revision++;
	// "M 0" to the proxy: the eyes render (from here, every 30 frames: this runs while the game is paused too,
	// when the controller doesn't tick and game time stands still)
	if ( ++Frames % 30 == 1 && PC.Link != None )
		PC.Link.ToProxy("M 0");
	C.Reset();
	C.Style = 1;   // STY_Normal (ERenderStyle lives in Actor)
	C.DrawColor = class'Canvas'.static.MakeColor(255, 255, 255);
	// the scope first: the eyes then draw its finished picture into their lens
	if ( PC.bScopeOn && PC.ScopeTex != None )
	{
		PC.ScopeTex.Revision++;
		C.SetPos(0, 0);
		C.DrawTile(PC.ScopeTex, 1, 1, 0, 0, 1, 1);
	}
	C.SetPos(0, 0);
	C.DrawTile(PC.EyeTex[0], 1, 1, 0, 0, 1, 1);
	C.SetPos(0, 0);
	C.DrawTile(PC.EyeTex[1], 1, 1, 0, 0, 1, 1);
}

defaultproperties
{
	bVisible=true
	bActive=false
}
