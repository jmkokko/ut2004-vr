//=============================================================================
// VRHUD: in VR the eyes render into the controller's two ScriptedTextures
// (Canvas.DrawPortal on the main canvas projects with the whole window's aspect, so
// side-by-side portals came out vertically stretched 2x). The window shows a mirror of
// both eyes, which also makes the engine update the render targets every frame.
//=============================================================================
class VRHUD extends HudCDeathMatch;

#exec TEXTURE IMPORT NAME=VRScopeMask FILE=Textures\ScopeMask.tga MIPS=OFF ALPHA=1 LODSET=LODSET_Interface UCLAMPMODE=CLAMP VCLAMPMODE=CLAMP
#exec TEXTURE IMPORT NAME=VRScopeRing FILE=Textures\ScopeRing.tga MIPS=OFF ALPHA=1 LODSET=LODSET_Interface UCLAMPMODE=CLAMP VCLAMPMODE=CLAMP
#exec TEXTURE IMPORT NAME=VRPorthole FILE=Textures\Porthole.tga MIPS=OFF ALPHA=1 LODSET=LODSET_Interface UCLAMPMODE=CLAMP VCLAMPMODE=CLAMP
#exec TEXTURE IMPORT NAME=VRVignette FILE=Textures\Vignette.tga MIPS=OFF ALPHA=1 LODSET=LODSET_Interface UCLAMPMODE=CLAMP VCLAMPMODE=CLAMP

var float MsgCullTime;              // Level.TimeSeconds the message queues were last aged
var int ScoreFrame;                 // frames the original scoreboard has been up (every ScoreCapturePeriod: a capture pair)
var int ScoreCapturePeriod;         // frames between scoreboard captures for the headset (two frames each)
var float ScoreSaidAt;              // "S 1" to the proxy (it watches for the capture frames while that keeps coming)

simulated event PostRender(Canvas C)
{
	local VRPlayerController PC;
	local ScriptedTexture T;
	local float HX, VY, PxPerTan, CX, CY;

	PC = VRPlayerController(PlayerOwner);
	if ( WantVRScoreboard(PC) )
	{
		// UT's own scoreboard for the headset (the desktop mirror shows it too: it's in the eye picture): every ScoreCapturePeriod frames it is drawn alone, over black and
		// then over white, with a marker the proxy recognises; the proxy recovers its transparency from the pair
		// (alpha = 1 - (white - black)) and shows it on a panel in front of you. The proxy puts the previous
		// window picture back for those two frames, so the desktop doesn't flash.
		ScoreFrame++;
		if ( PC.Link != None && (Level.TimeSeconds - ScoreSaidAt > 0.25 || Level.TimeSeconds < ScoreSaidAt) )
		{
			ScoreSaidAt = Level.TimeSeconds;
			PC.Link.ToProxy("S 1");
		}
		if ( ScoreFrame % ScoreCapturePeriod == 1 || ScoreFrame % ScoreCapturePeriod == 2 )
		{
			DrawScoreCapture(C, ScoreFrame % ScoreCapturePeriod == 2);
			return;
		}
	}
	else if ( ScoreFrame > 0 )
	{
		ScoreFrame = 0;
		if ( PC != None && PC.Link != None )
			PC.Link.ToProxy("S 0");
	}
	if ( PC == None || !PC.VRActive() || PC.EyeTex[0] == None || PC.EyeTex[1] == None
		|| (!PC.IsInState('Dead') && (PC.Pawn == None || PC.ViewTarget != PC.Pawn || PC.bBehindView)) )
	{
		Super.PostRender(C);
		return;
	}

	// Mirror backdrop: the eye image rendered at the end of the previous frame (its revision is unchanged here,
	// so drawing it does not re-render it and the D3D9Drv render-target bug doesn't kick in). The console and
	// menus are drawn over it afterwards; VRMirrorInteraction renders the eyes last.
	C.Reset();
	C.Style = ERenderStyle.STY_Normal;
	C.DrawColor = WhiteColor;
	PC.WinW = C.ClipX;
	PC.WinH = C.ClipY;
	if ( PC.bMenuOpen )
	{
		// the menu goes on black: the proxy copies the window into the headset as a floating panel
		C.DrawColor.R = 0; C.DrawColor.G = 0; C.DrawColor.B = 0; C.DrawColor.A = 255;
		C.SetPos(0, 0);
		C.DrawTile(Texture'Engine.WhiteSquareTexture', C.ClipX, C.ClipY, 0, 0, 2, 2);
		C.DrawColor = WhiteColor;
	}
	else if ( PC.MirrorEye == 0 || PC.MirrorEye == 1 )
	{
		T = PC.EyeTex[PC.MirrorEye];
		HX = PC.MirrorHX;
		VY = PC.MirrorVY;
		CX = 0;
		CY = 0;
		if ( HX > 0 && VY > 0 )
		{
			if ( PC.bVRHud && PC.bMirrorFitHud && !PC.IsCinematic() )
				MirrorFitHud(PC, C, HX, VY, CX, CY);
			// crop to the window shape around (CX, CY): straight ahead, or the HUD's centre
			else if ( HX / VY > C.ClipX / C.ClipY )
				HX = VY * C.ClipX / C.ClipY;
			else
				VY = HX * C.ClipY / C.ClipX;
			PxPerTan = T.USize * 0.5 / Tan(PC.EyeFOV * 0.5 * 3.14159265 / 180.0);
			C.SetPos(0, 0);
			C.DrawTile(T, C.ClipX, C.ClipY, T.USize * 0.5 + (CX - HX) * PxPerTan, T.VSize * 0.5 - (CY + VY) * PxPerTan, 2 * HX * PxPerTan, 2 * VY * PxPerTan);
		}
	}
}

// the desktop window, cropped around the VR HUD: its corners (with a margin) just fit the window, whatever its
// aspect, and the HUD is centred in it (the HUD sits lower than straight ahead with HudBottomUp/HudLower, so a
// crop around straight ahead cut its bottom row off in wide windows). Tangents of the mirrored eye's view; the
// eye sits half the IPD beside the head, which shifts the HUD by that much at its distance.
simulated function MirrorFitHud(VRPlayerController PC, Canvas C, out float HX, out float VY, out float CX, out float CY)
{
	local float K, Top, Bottom, HalfW, A, Lim;

	K = PC.HudSpread / PC.HudDistance;
	HalfW = (0.62 + PC.MirrorHudMargin) * K;
	Top = (PC.HudTopUp - PC.HudLower + PC.MirrorHudMargin) * K;
	Bottom = (PC.HudBottomUp - PC.HudLower - PC.MirrorHudMargin) * K;
	CY = (Top + Bottom) * 0.5;
	VY = (Top - Bottom) * 0.5;
	CX = 0.032 / PC.HudDistance;
	if ( PC.MirrorEye == 1 )
		CX = -CX;
	A = C.ClipX / C.ClipY;
	if ( HalfW / VY > A )
		VY = HalfW / A;
	HX = VY * A;
	// never past the rendered eye image
	Lim = Tan(PC.EyeFOV * 0.5 * 3.14159265 / 180.0);
	if ( Abs(CX) + HX > Lim )
	{
		HX = Lim - Abs(CX);
		VY = HX / A;
	}
	if ( Abs(CY) + VY > Lim )
	{
		VY = Lim - Abs(CY);
		HX = VY * A;
	}
}

// the original scoreboard in the headset: shown while UT's own show-scores is on (also while dead) or the VR
// scoreboard button / VRScores; bVRScoreboardOriginal=False keeps the drawn VR HUD scoreboard instead
simulated function bool WantVRScoreboard(VRPlayerController PC)
{
	return PC != None && PC.VRActive() && PC.bVRScoreboardOriginal && ScoreBoard != None && !PC.bMenuOpen
		&& !PC.IsCinematic() && (bShowScoreBoard || PC.bShowVRScores);
}

// one capture frame: the scoreboard alone on black (0) or white (1), and a two-pixel marker at the bottom right
// (the top left gets the eye-render tiles VRMirrorInteraction draws last)
simulated function DrawScoreCapture(Canvas C, bool bWhite)
{
	local color K;

	C.Reset();
	C.Style = ERenderStyle.STY_Normal;
	if ( bWhite )
		C.DrawColor = WhiteColor;
	else
	{
		C.DrawColor.R = 0; C.DrawColor.G = 0; C.DrawColor.B = 0; C.DrawColor.A = 255;
	}
	C.SetPos(0, 0);
	C.DrawTile(Texture'Engine.WhiteSquareTexture', C.ClipX, C.ClipY, 0, 0, 2, 2);
	C.Reset();
	ScoreBoard.DrawScoreboard(C);
	// marker: black frame magenta, green; white frame cyan, red (the proxy checks both pixels)
	C.Reset();
	C.Style = ERenderStyle.STY_Normal;
	K.A = 255;
	K.R = 255; K.G = 0; K.B = 255;
	if ( bWhite ) { K.R = 0; K.G = 255; K.B = 255; }
	C.DrawColor = K;
	C.SetPos(C.ClipX - 2, C.ClipY - 1);
	C.DrawTile(Texture'Engine.WhiteSquareTexture', 1, 1, 0, 0, 2, 2);
	K.R = 0; K.G = 255; K.B = 0;
	if ( bWhite ) { K.R = 255; K.G = 0; K.B = 0; }
	C.DrawColor = K;
	C.SetPos(C.ClipX - 1, C.ClipY - 1);
	C.DrawTile(Texture'Engine.WhiteSquareTexture', 1, 1, 0, 0, 2, 2);
}

// UT's game messages in VR (see VRPlayerController.MsgPoint): HudBase only draws its two queues from the 2D
// PostRender, which VR skips, so the eyes draw them here (the queues are too big to read from another class)

// age the queues like HudBase.DisplayLocalMessages / HUD.DisplayMessages do (once per frame, not per eye)
simulated function AgeVRMessages()
{
	local int i, j;

	for ( i = 0; i < ArrayCount(LocalMessages); i++ )
	{
		if ( LocalMessages[i].Message == None )
			break;
		if ( LocalMessages[i].Message.default.bFadeMessage && LocalMessages[i].EndOfLife <= Level.TimeSeconds )
		{
			for ( j = i; j < ArrayCount(LocalMessages) - 1; j++ )
				LocalMessages[j] = LocalMessages[j + 1];
			ClearMessage(LocalMessages[j]);
			i--;
		}
	}
	for ( i = 0; i < ConsoleMessageCount && i < ArrayCount(TextMessages); i++ )
	{
		if ( TextMessages[i].Text == "" )
			break;
		if ( TextMessages[i].MessageLife < Level.TimeSeconds )
		{
			for ( j = i; j < ArrayCount(TextMessages) - 1; j++ )
				TextMessages[j] = TextMessages[j + 1];
			TextMessages[j].Text = "";
			i--;
		}
	}
}

simulated function DrawVRMessages(VRPlayerController PC, ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local int i, j, Count, W, Ht, Steps;
	local float VW, PX, PY, Fade, Off;
	local float PosX[8], PosY[8], Below;
	local EDrawPivot Piv[8];
	local LocalMessage.EStackMode Stack[8];
	local Font F;
	local color C;
	local class<LocalMessage> M;

	if ( MsgCullTime != Level.TimeSeconds )
	{
		MsgCullTime = Level.TimeSeconds;
		AgeVRMessages();
	}
	// the virtual screen's width in this eye's pixels: fonts are fixed-size bitmaps, so this picks the same
	// font UT would pick for a monitor that wide, and the text covers the same share of the screen
	VW = Tex.USize * (1.24 * PC.HudSpread / PC.HudDistance) * 0.5 / Tan(PC.EyeFOV * 0.5 * 3.14159265 / 180.0);
	Steps = PC.MsgFontSteps(VW);

	// special messages: each at its class's position and pivot; ones sharing a stack go under (or over) the first
	for ( i = 0; i < ArrayCount(LocalMessages); i++ )
	{
		M = LocalMessages[i].Message;
		if ( M == None )
			break;
		M.static.GetPos(LocalMessages[i].Switch, Piv[i], Stack[i], PosX[i], PosY[i]);
		F = LoadFont(Clamp(8 - (M.static.GetFontSize(LocalMessages[i].Switch, LocalMessages[i].RelatedPRI,
			LocalMessages[i].RelatedPRI2, PC.PlayerReplicationInfo) + MessageFontOffset + Steps), 0, 8));
		if ( F == None || !PC.MsgPoint(Tex, Loc, Rot, PosX[i], PosY[i], PX, PY) )
			continue;
		C = M.static.GetColor(LocalMessages[i].Switch, LocalMessages[i].RelatedPRI, LocalMessages[i].RelatedPRI2);
		if ( M.default.bFadeMessage && LocalMessages[i].LifeTime > 0 )
		{
			Fade = FClamp((LocalMessages[i].EndOfLife - Level.TimeSeconds) / LocalMessages[i].LifeTime, 0, 1);
			C.A = byte(C.A * Fade);
		}
		Tex.TextSize(LocalMessages[i].StringMessage, F, W, Ht);
		// stacking: the earlier messages in the same stack push this one down (SM_Down) or up (SM_Up)
		Off = 0;
		if ( Stack[i] != SM_None )
			for ( j = 0; j < i; j++ )
				if ( Stack[j] == Stack[i] && Piv[j] == Piv[i] && PosX[j] == PosX[i] && PosY[j] == PosY[i] )
					Off += Ht;
		if ( Stack[i] == SM_Up )
			PY -= Off;
		else
			PY += Off;
		switch ( Piv[i] )
		{
			case DP_UpperLeft:                                      break;
			case DP_UpperMiddle:  PX -= W / 2;                      break;
			case DP_UpperRight:   PX -= W;                          break;
			case DP_MiddleLeft:                PY -= Ht / 2;        break;
			case DP_MiddleRight:  PX -= W;     PY -= Ht / 2;        break;
			case DP_LowerLeft:                 PY -= Ht;            break;
			case DP_LowerMiddle:  PX -= W / 2; PY -= Ht;            break;
			case DP_LowerRight:   PX -= W;     PY -= Ht;            break;
			default:              PX -= W / 2; PY -= Ht / 2;        break;
		}
		PC.MsgText(Tex, PX, PY, LocalMessages[i].StringMessage, F, C);
	}

	// console messages (kills, chat, joins): lower left, newest at the bottom, as HUD.DisplayMessages
	for ( Count = 0; Count < ConsoleMessageCount && Count < ArrayCount(TextMessages); Count++ )
		if ( TextMessages[Count].Text == "" )
			break;
	if ( Count == 0 || !PC.MsgPoint(Tex, Loc, Rot, ConsoleMessagePosX, ConsoleMessagePosY, PX, PY) )
		return;
	F = LoadFont(Clamp(ConsoleFontSize + 6 - Steps, 0, 8));
	if ( F == None )
		return;
	Tex.TextSize("A", F, W, Ht);
	Below = PY - Ht * (Count + 1);   // one free line under them, where UT puts the typing prompt
	for ( i = 0; i < Count; i++ )
		PC.MsgText(Tex, PX, Below + Ht * i, TextMessages[i].Text, F, TextMessages[i].TextColor);
}


defaultproperties
{
	ScoreCapturePeriod=8
}
