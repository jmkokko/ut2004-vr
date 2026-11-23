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
#exec TEXTURE IMPORT NAME=VRLaserDot FILE=Textures\LaserDot.tga MIPS=ON UCLAMPMODE=CLAMP VCLAMPMODE=CLAMP

var float MsgCullTime;              // Level.TimeSeconds the message queues were last aged
var int ScoreFrame;                 // frames an original overlay has been up (every ScoreCapturePeriod: a capture pair)
var int OverlayKind;                // that overlay: 1 UT's scoreboard, 2 UT's spectator bar (DrawSpectatingHud), 3 the game type's HUD
var bool bDebugShowCapture;         // debug (VRShowCapture): the window shows the capture frame (over black) all the time
var float CineStart;                // when the Matinee intro began (the title's clock)
var HudBase Shadow;                 // the game type's own HUD (HUD_Assault, HudCDeathMatch...), drawn only for the capture
var float OverlayTop;               // the window share the overlay covers, from the top (0..1; the bar: its top edge)
var int ScoreCapturePeriod;         // frames between scoreboard captures for the headset (two frames each)
var float ScoreSaidAt;              // "S 1" to the proxy (it watches for the capture frames while that keeps coming)

simulated event PostRender(Canvas C)
{
	local VRPlayerController PC;
	local ScriptedTexture T;
	local float HX, VY, PxPerTan, CX, CY;
	local int K;

	PC = VRPlayerController(PlayerOwner);
	K = VROverlay(PC);
	if ( K != OverlayKind )
		ScoreFrame = 0;
	OverlayKind = K;
	if ( K > 0 )
	{
		// UT's own scoreboard or spectator bar for the headset (the desktop mirror shows it too: it's in the eye
		// picture). Every ScoreCapturePeriod frames it is drawn alone, over black and then over white, with a marker
		// the proxy recognises; the proxy recovers its transparency from the pair (alpha = 1 - (white - black)) and
		// shows it on a panel in front of you (the spectator bar: only its strip, lower down). The proxy puts the
		// previous window picture back for those two frames, so the desktop doesn't flash.
		ScoreFrame++;
		if ( bDebugShowCapture && ScoreFrame % ScoreCapturePeriod > 2 )
		{
			DrawScoreCapture(C, false);
			C.SetPos(C.ClipX - 2, C.ClipY - 1);   // no marker: not a capture frame for the proxy
			C.DrawColor.R = 0; C.DrawColor.G = 0; C.DrawColor.B = 0; C.DrawColor.A = 255;
			C.DrawTile(Texture'Engine.WhiteSquareTexture', 2, 1, 0, 0, 2, 2);
			return;
		}
		if ( ScoreFrame % ScoreCapturePeriod == 1 || ScoreFrame % ScoreCapturePeriod == 2 )
		{
			DrawScoreCapture(C, ScoreFrame % ScoreCapturePeriod == 2);
			// "S <kind> <top>": what is up and the window share it covers
			if ( PC.Link != None && (Level.TimeSeconds - ScoreSaidAt > 0.25 || Level.TimeSeconds < ScoreSaidAt) )
			{
				ScoreSaidAt = Level.TimeSeconds;
				// "S 3 0 <distance> <half width> <centre up>": the HUD layer where the VR HUD's corners are
				if ( K == 3 )
					PC.Link.ToProxy("S 3 0 " $ PC.HudDistance $ " " $ PC.LayerHalfRight() $ " " $ PC.LayerCentreUp());
				else
					PC.Link.ToProxy("S " $ K $ " " $ OverlayTop);
			}
			return;
		}
	}
	else if ( ScoreFrame > 0 || ScoreSaidAt > 0 )
	{
		ScoreFrame = 0;
		ScoreSaidAt = 0;
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

// UT's own overlays in the headset: 1 the scoreboard, while UT's own show-scores is on (also while dead) or the VR
// scoreboard button / VRScores; 2 the spectator bar while spectating; 0 none. bVRScoreboardOriginal=False keeps
// the drawn VR HUD versions instead.
simulated function int VROverlay(VRPlayerController PC)
{
	if ( PC == None || !PC.VRActive() || !PC.bVRScoreboardOriginal || PC.bMenuOpen )
		return 0;
	// a Matinee intro in a game (Assault's briefing): the game type's HUD draws its title and captions then
	if ( PC.IsCinematic() )
	{
		if ( PC.bViewingMatineeCinematic && CinematicGame(Level.Game) == None && Shadow != None && PC.bVROriginalHud )
			return 3;
		return 0;
	}
	if ( PC.IsVRSpectating() )
		return 2;
	// the game type's HUD, with the scoreboard in its place while it is up (F1, or while dead), as in 2D
	if ( HudLayerUp(PC) )
		return 3;
	// no original HUD (bVROriginalHud off): the scoreboard alone, on its own panel
	if ( ScoreBoard != None && WantScores(PC) )
		return 1;
	return 0;
}

simulated function bool WantScores(VRPlayerController PC)
{
	return bShowScoreBoard || PC.bShowVRScores;
}

// 3: the game type's HUD layer (alive or dead, not spectating)
simulated function bool HudLayerUp(VRPlayerController PC)
{
	return Shadow != None && PC.bVROriginalHud && PC.bVRHud && (!bHideHUD || PC.bViewingMatineeCinematic);
}

// the game type's own HUD beside this one: it ticks on its own (pulses, objectives, countdown announcements), and
// VRHUD draws it only into the capture. What the game tells the HUD directly is passed on (hits, announcements).
simulated function SetShadow(class<HUD> C)
{
	if ( Shadow != None )
		Shadow.Destroy();
	Shadow = HudBase(Spawn(C, Owner));
	if ( Shadow == None )
		return;
	// in 3D instead (or not at all): the crosshair (the laser), the world-pointing Assault markers
	Shadow.bCrosshairShow = false;
	Shadow.SetPropertyText("bOnHUDObjectiveNotification", "False");
	Shadow.SetPropertyText("bShowInfoPods", "False");
	Shadow.SetPropertyText("bShow3DArrow", "False");
	Shadow.SetPropertyText("HealthBarViewDist", "0");   // Onslaught's node / core health bars (drawn at screen positions)
	Log("UT2004VR: original HUD "$Shadow$" captured for the headset", 'UT2004VR');
	// Onslaught's menu map tab reads its HUD through myHUD: the VR tab hands it this one
	if ( ONSHUDOnslaught(Shadow) != None )
		class'UT2K4OnslaughtLoginMenu'.default.OnslaughtMapPanel.ClassName = "UT2004VR.VROnslaughtMap";
}

// UT's own 2D message drawing into the HUD layer: the special messages, the console lines and the typing prompt
simulated function DrawLayerMessages(Canvas C, Console Con, bool bTyping)
{
	local Plane OldCM;
	C.Reset();
	OldCM = C.ColorModulate;
	DisplayLocalMessages(C);
	C.ColorModulate = OldCM;
	C.Reset();
	DisplayMessages(C);
	if ( Con != None && bTyping )
	{
		C.Reset();
		DrawTypingPrompt(C, Con.TypedStr, Con.TypedStrPos);
	}
}

// the countdown announcements ("five minutes remain"...) come from the game type's HUD when it runs beside this one
function CheckCountdown(GameReplicationInfo GRI)
{
	if ( Shadow == None )
		Super.CheckCountdown(GRI);
}

simulated event Destroyed()
{
	if ( Shadow != None )
		Shadow.Destroy();
	Super.Destroyed();
}

simulated function DisplayHit(vector HitDir, int Damage, class<DamageType> damageType)
{
	Super.DisplayHit(HitDir, Damage, damageType);
	if ( Shadow != None )
		Shadow.DisplayHit(HitDir, Damage, damageType);
}

// a teammate's voice message (TeamVoicePack) or chat (Message, via HudCDeathMatch) shows the speaker's portrait:
// UT tells this HUD, the game type's HUD beside it draws the portrait into the captured layer
// the announcer's events: Assault's HUD highlights the current objective and shows the way there (the trail)
event AnnouncementPlayed(Name AnnouncerSound, byte Switch)
{
	Super.AnnouncementPlayed(AnnouncerSound, Switch);
	if ( Shadow != None )
		Shadow.AnnouncementPlayed(AnnouncerSound, Switch);
	Log("UT2004VR: announcement "$AnnouncerSound$" ("$Switch$") passed to "$Shadow, 'UT2004VR');
}

simulated function DisplayPortrait(PlayerReplicationInfo PRI)
{
	Super.DisplayPortrait(PRI);
	if ( Shadow != None && PRI != None )
		Shadow.DisplayPortrait(PRI);
}

// the HUD settings (Settings > HUD and the crosshair page) are made on this HUD and saved: the game type's HUD beside
// it read them only when it was created, so they are passed on before each capture
simulated function SyncShadow()
{
	Shadow.bHideHUD = bHideHUD;   // (a cinematic hides it: then only its title and captions)
	Shadow.bShowWeaponInfo = bShowWeaponInfo;
	Shadow.bShowPersonalInfo = bShowPersonalInfo;
	Shadow.bShowPoints = bShowPoints;
	// its own scoreboard of the game type's class: without one HudCDeathMatch.UpdateRankAndSpread returns before
	// drawing your frags, the spread to the leader and your rank (top left). Its own, as a HUD destroys its scoreboard.
	if ( ScoreBoard != None && (Shadow.ScoreBoard == None || Shadow.ScoreBoard.Class != ScoreBoard.Class) )
		Shadow.SetScoreBoardClass(ScoreBoard.Class);
	Shadow.bShowWeaponBar = bShowWeaponBar;
	Shadow.bSmallWeaponBar = bSmallWeaponBar;
	Shadow.bShowPortrait = bShowPortrait;
	Shadow.bShowPortraitVC = bShowPortraitVC;
	Shadow.bNoEnemyNames = bNoEnemyNames;
	// voice chat (VoIP): the engine marks who is talking on this HUD only
	Shadow.LastPlayerIDTalking = LastPlayerIDTalking;
	if ( Shadow.LastPlayerIDTalkingTime != LastPlayerIDTalkingTime )
		Shadow.SetPropertyText("LastPlayerIDTalkingTime", GetPropertyText("LastPlayerIDTalkingTime"));
	Shadow.HudScale = HudScale;
	Shadow.HudOpacity = HudOpacity;
	Shadow.HudCanvasScale = HudCanvasScale;
	Shadow.CrosshairStyle = CrosshairStyle;
	Shadow.CrosshairScale = CrosshairScale;
	Shadow.CrosshairColor = CrosshairColor;
	if ( Shadow.CustomHUDColor != class'HudBase'.default.CustomHUDColor )
	{
		Shadow.CustomHUDColor = class'HudBase'.default.CustomHUDColor;
		Shadow.SetCustomHUDColor();
	}
}

// the game type's HUD alone: no first-person gun (UT draws it from the HUD, but not in behind view), no typing prompt
simulated function DrawShadowHud(Canvas C)
{
	local bool bOldBehind, bOldTyping;
	local Console Con;
	local HUD_Assault AH;
	local Vehicle TV;
	local float TVSearch;
	local GameObject GObj;
	local Pawn P;
	local bool bOldSpecialCH, bOldSpecialHUD;
	local Vehicle FTarget;
	local ONSVehicle OV;
	local ONSWeaponPawn WP;
	local float CHX, CHY;

	SyncShadow();
	bOldBehind = PlayerOwner.bBehindView;
	PlayerOwner.bBehindView = true;
	if ( PlayerOwner.Player != None )
		Con = PlayerOwner.Player.Console;
	if ( Con != None )
	{
		bOldTyping = Con.bTyping;
		Con.bTyping = false;
	}
	// the scoreboard replaces the HUD while it is up, as HUD.PostRender does in 2D
	if ( ScoreBoard != None && WantScores(VRPlayerController(PlayerOwner)) )
	{
		C.Reset();
		ScoreBoard.DrawScoreboard(C);
		if ( ScoreBoard.bDisplayMessages )
			DrawLayerMessages(C, Con, bOldTyping);
		PlayerOwner.bBehindView = bOldBehind;
		if ( Con != None )
			Con.bTyping = bOldTyping;
		return;
	}
	Shadow.bShowScoreBoard = false;
	// Assault's tracked vehicle and game object are drawn in 3D (VRGameMarkers): out of the captured picture
	AH = HUD_Assault(Shadow);
	if ( AH != None )
	{
		TV = AH.TrackedVehicle;
		TVSearch = AH.NextTrackedVehicleSearch;
		AH.TrackedVehicle = None;
		AH.NextTrackedVehicleSearch = Level.TimeSeconds + 10;
		if ( AH.ASGRI != None )
		{
			GObj = AH.ASGRI.GameObject;
			AH.ASGRI.GameObject = None;
		}
	}
	// a vehicle's own crosshair (Assault turrets: at the screen position of their aim, plus a green "will hit"
	// square) is drawn in 3D instead
	P = PlayerOwner.Pawn;
	if ( P != None )
	{
		bOldSpecialCH = P.bSpecialCrosshair;
		P.bSpecialCrosshair = false;
		// the guided Redeemer's own HUD (HUD.PostRender -> Pawn.DrawHUD) is 2D's full-screen scope picture: on the
		// layer it hid the whole view. You ride behind its window in 3D instead (DrawRedeemerWindow)
		bOldSpecialHUD = P.bSpecialHUD;
		P.bSpecialHUD = false;
	}
	// a space fighter's target box / line (at the target's screen position): in 3D instead
	if ( ASVehicle_SpaceFighter(P) != None )
	{
		FTarget = ASVehicle_SpaceFighter(P).CurrentTarget;
		ASVehicle_SpaceFighter(P).CurrentTarget = None;
	}
	// an Onslaught vehicle's / turret's "barrel aligned" crosshair (at the screen centre = the view, not the gun): in
	// 3D instead (VRGameMarkers); zero-sized for the capture (its tile is CrosshairX * 2 + 1 wide)
	OV = ONSVehicle(P);
	WP = ONSWeaponPawn(P);
	if ( OV != None )
	{
		CHX = OV.CrosshairX; CHY = OV.CrosshairY;
		OV.CrosshairX = -0.5; OV.CrosshairY = -0.5;
	}
	else if ( WP != None )
	{
		CHX = WP.CrosshairX; CHY = WP.CrosshairY;
		WP.CrosshairX = -0.5; WP.CrosshairY = -0.5;
	}
	// a Matinee intro: only its title (Assault's, by its own clock: IntroTitleFade += Global_Delta per draw, and the
	// copy draws every few frames, so it gets the real time since the intro began) and its captions - not the
	// rest of the cinematic HUD, whose film grain, captured a few times a second and fixed to your head, would be
	// flickering static
	if ( PlayerOwner.bViewingMatineeCinematic )
	{
		if ( CineStart == 0 )
			CineStart = Level.TimeSeconds;
		C.Reset();
		if ( AH != None )
		{
			AH.IntroTitleFade = Level.TimeSeconds - CineStart;
			if ( AH.IntroTitleFade < 10 )
				AH.DrawIntroTitle(C);
		}
		C.Reset();
		if ( Shadow.SubTitles != None )
			Shadow.DrawIntroSubtitles(C);
	}
	else
	{
		CineStart = 0;
		Shadow.PostRender(C);
	}
	if ( OV != None )
	{
		OV.CrosshairX = CHX; OV.CrosshairY = CHY;
	}
	else if ( WP != None )
	{
		WP.CrosshairX = CHX; WP.CrosshairY = CHY;
	}
	if ( P != None )
	{
		P.bSpecialCrosshair = bOldSpecialCH;
		P.bSpecialHUD = bOldSpecialHUD;
	}
	// the game messages go on top of the HUD, as in 2D (in the eyes they were under the layer)
	DrawLayerMessages(C, Con, bOldTyping);
	if ( ASVehicle_SpaceFighter(P) != None )
		ASVehicle_SpaceFighter(P).CurrentTarget = FTarget;
	if ( AH != None )
	{
		AH.TrackedVehicle = TV;
		AH.NextTrackedVehicleSearch = TVSearch;
		if ( AH.ASGRI != None )
			AH.ASGRI.GameObject = GObj;
	}
	PlayerOwner.bBehindView = bOldBehind;
	if ( Con != None )
		Con.bTyping = bOldTyping;
}

// one capture frame: the overlay alone on black (0) or white (1), and a two-pixel marker at the bottom right
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
	if ( OverlayKind == 3 )
	{
		DrawShadowHud(C);
		OverlayTop = 0;
	}
	else if ( OverlayKind == 2 )
	{
		DrawSpectatingHud(C);
		OverlayTop = SpectatorBarTop(C) / C.ClipY;
	}
	else
	{
		ScoreBoard.DrawScoreboard(C);
		OverlayTop = 0;
	}
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

// the top of what DrawSpectatingHud draws (its layout: the bar above the bottom edge, the LMS logo poking 8 px above
// it, the tag line one console line above that), with a little room
simulated function float SpectatorBarTop(Canvas C)
{
	local float XL, MedH, SmallH, Full, Top;

	C.Font = GetMediumFontFor(C);
	C.StrLen("W", XL, MedH);
	C.Font = GetConsoleFont(C);
	C.StrLen("W", XL, SmallH);
	Full = MedH + SmallH;
	Top = C.ClipY - 8 - Full;
	return FMax(0, FMin(Top - 8, Top - 3 - SmallH) - 6);
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
	local bool bTyping;

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
	bTyping = PlayerConsole != None && PlayerConsole.bTyping;
	if ( (Count == 0 && !bTyping) || !PC.MsgPoint(Tex, Loc, Rot, ConsoleMessagePosX, ConsoleMessagePosY, PX, PY) )
		return;
	F = LoadFont(Clamp(ConsoleFontSize + 6 - Steps, 0, 8));
	if ( F == None )
		return;
	Tex.TextSize("A", F, W, Ht);
	Below = PY - Ht * (Count + 1);   // one free line under them, where UT puts the typing prompt
	for ( i = 0; i < Count; i++ )
		PC.MsgText(Tex, PX, Below + Ht * i, TextMessages[i].Text, F, TextMessages[i].TextColor);
	// the typing prompt (T: say, Y: team say, the console's own line), as HUD.DrawTypingPrompt draws it
	if ( bTyping )
		PC.MsgText(Tex, PX, PY - Ht, "(>" @ Left(PlayerConsole.TypedStr, PlayerConsole.TypedStrPos) $ Chr(4)
			$ Eval(PlayerConsole.TypedStrPos < Len(PlayerConsole.TypedStr), Mid(PlayerConsole.TypedStr, PlayerConsole.TypedStrPos), "_"),
			F, ConsoleColor);
}


defaultproperties
{
	ScoreCapturePeriod=8
}
