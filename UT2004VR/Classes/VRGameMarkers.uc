//=============================================================================
// VRGameMarkers: the game types' world-pointing HUD markers in VR. The game type's own HUD (VRHUD.Shadow) goes into
// the headset as a captured layer, but what it draws at the screen position of something in the world would sit in
// the wrong place there, so those markers are drawn here instead: projected from the world point into each eye
// (they sit on the objective, at its depth), with the HUD's own textures, colours, pulse and rules.
// Assault (HUD_Assault): objectives (icon, defender shield, progress bar; blocked: small icon + distance; out of
// view: an arrow at the edge of the HUD layer), the tracked vehicle and the tracked game object (JunkYard's core).
//=============================================================================
class VRGameMarkers extends Object;

var TexRotator Arrows[8];           // the out-of-view arrows (one per objective drawn this eye)
var int ArrowCount;
var float NextAimLog;               // debug: DrawONSCrosshair's log

// the HUD's ResScale for the HUD layer (a virtual 16:9 screen as wide as the layer, in this eye's pixels)
static function float LayerRes(VRPlayerController PC, ScriptedTexture Tex)
{
	return PC.LayerPixels(Tex) / 853.0;
}

// a world point -> pixel in this eye; false when behind the eye or outside the picture
static function bool InView(VRPlayerController PC, ScriptedTexture Tex, vector P, vector Loc, rotator Rot, out float PX, out float PY)
{
	if ( !PC.HudProject(Tex, P, Loc, Rot, PX, PY) )
		return false;
	return PX >= 0 && PX <= Tex.USize && PY >= 0 && PY <= Tex.VSize;
}

function DrawAssault(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local int i;
	local GameObjective GO;
	local float PX, PY, RS, Prog;
	local color C;
	local byte bPulse;
	local Vehicle V;

	if ( H == None || PC.Pawn == None )
		return;
	RS = LayerRes(PC, Tex);
	ArrowCount = 0;

	// objectives (HUD_Assault.DrawObjectives)
	if ( H.default.bOnHUDObjectiveNotification )
		for ( i = 0; i < H.OBJ.Length; i++ )
		{
			GO = H.OBJ[i];
			if ( GO == None || !GO.IsActive() || !GO.bUsePriorityOnHUD || !H.CheckObjectivePriority(GO) )
				continue;
			C = H.GetObjectiveColor(GO, bPulse);
			Prog = GO.GetObjectiveProgress();
			if ( InView(PC, Tex, GO.Location, Loc, Rot, PX, PY) )
			{
				if ( ObjectiveVisible(PC, H, GO) )
					DrawVisibleObjective(PC, H, Tex, GO, PX, PY, C, bPulse, Prog, RS);
				else
				{
					C.A = 128;
					DrawObstructed(PC, H, Tex, GO, GO.bOptionalObjective, PX, PY, C, RS);
					if ( Prog > 0 )
						DrawStatusOverlay(H, Tex, PX, PY, Prog, H.ObjectiveScale * 0.67, RS);
					if ( GO.IsCritical() )
						DrawCriticalOverlay(H, Tex, PX, PY, H.ObjectiveScale, RS);
				}
			}
			else if ( H.bDrawAllObjectives )
			{
				DrawBehind(PC, H, Tex, GO, GO.bOptionalObjective, Loc, Rot, PX, PY, C, RS);
				if ( Prog > 0 )
					DrawStatusOverlay(H, Tex, PX, PY, Prog, H.ObjectiveScale * 0.67, RS);
				if ( GO.IsCritical() )
					DrawCriticalOverlay(H, Tex, PX, PY, H.ObjectiveScale * 0.60, RS);
			}
		}

	// the tracked vehicle and game object (HUD_Assault.UpdateActorTracking; the captured HUD skips them)
	V = H.TrackedVehicle;
	if ( V != None && V != PC.Pawn && V.Health > 0 && !V.bDeleteMe )
	{
		C = class'HUD_Assault'.static.GetTeamColor(V.Team);
		C.A = 128;
		if ( DrawTracking(PC, H, Tex, V, Loc, Rot, PX, PY, C, RS) )
			DrawVehicleIcon(H, Tex, V, PX, PY, RS);
	}
	if ( H.ASGRI != None && H.ASGRI.GameObject != None && H.ASGRI.GameObject.HolderPRI != PC.Pawn.PlayerReplicationInfo )
	{
		C = H.GoldColor;
		C.A = 128;
		if ( DrawTracking(PC, H, Tex, H.ASGRI.GameObject, Loc, Rot, PX, PY, C, RS) )
		{
			C = H.WhiteColor;
			C.A = 127 + 128 * H.fPulse;
			Tex.DrawTile(PX - 8 * RS * H.ObjectiveScale * H.HUDScale, PY - 16 * RS * H.ObjectiveScale * H.HUDScale,
				16 * RS * H.ObjectiveScale * H.HUDScale, 16 * RS * H.ObjectiveScale * H.HUDScale, 79, 223, 37, 41,
				Material'HudContent.Generic.HUD', C);
		}
	}
}

// an Assault vehicle's / turret's crosshair (ASVehicle.SpecialDrawCrosshair): at the point its gun hits, with the
// green square when the shot will reach it; the captured HUD leaves it out (it sits at a screen position)
function DrawASVehicleCrosshair(VRPlayerController PC, ASVehicle V, ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local vector HL, HN;
	local float PX, PY, R, TX, TY;
	local color W, G;

	if ( V.Health < 1 || V.DefaultCrosshair == None )
		return;
	if ( V.CalcWeaponFire(HL, HN) == None )
		HL = V.GetCrosshairWorldLocation();
	if ( !InView(PC, Tex, HL, Loc, Rot, PX, PY) )
		return;
	R = PC.LayerPixels(Tex) / 640.0;
	TX = V.CrosshairScale * V.DefaultCrosshair.MaterialUSize() * R;
	TY = V.CrosshairScale * V.DefaultCrosshair.MaterialVSize() * R;
	W.R = 255; W.G = 255; W.B = 255; W.A = 255;
	Tex.DrawTile(PX - TX * 0.5, PY - TY * 0.5, TX, TY, 0, 0, V.DefaultCrosshair.MaterialUSize(), V.DefaultCrosshair.MaterialVSize(),
		V.DefaultCrosshair, W);
	if ( V.CrosshairHitFeedbackTex != None && V.WeaponHitsCrosshairsHL() )
	{
		G.R = 0; G.G = 255; G.B = 0; G.A = 192;
		Tex.DrawTile(PX - 16 * R, PY - 16 * R, 32 * R, 32 * R, 0, 0, V.CrosshairHitFeedbackTex.MaterialUSize(),
			V.CrosshairHitFeedbackTex.MaterialVSize(), V.CrosshairHitFeedbackTex, G);
	}
}

// a space fighter's target (ASVehicle_SpaceFighter_Human.DrawTargetting): UT's green brackets around the target's
// collision box, projected into this eye; out of view, a green arrow at the layer's edge. It also picks the target
// when asked (bTargetClosestToCrosshair; UT does it while drawing the crosshair, from screen positions): the
// relevant vehicle in sight nearest to the fighter's aim
function DrawFighterTarget(VRPlayerController PC, ASVehicle_SpaceFighter F, HUD_Assault H, ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local Vehicle V, Best, T;
	local vector Aim, Start, Corner;
	local float Dot, BestDot, PX, PY, X0, Y0, X1, Y1, BX, BY, RS;
	local int i;
	local bool bAny;
	local color C;

	if ( F.bTargetClosestToCrosshair )
	{
		Start = F.GetFireStart();
		Aim = Normal(F.GetCrosshairWorldLocation() - Start);
		BestDot = -2;
		foreach F.DynamicActors(class'Vehicle', V)
			if ( F.IsTargetRelevant(V) && F.LineOfSightTo(V) )
			{
				Dot = Normal(V.Location - Start) dot Aim;
				if ( Dot > BestDot )
				{
					BestDot = Dot;
					Best = V;
				}
			}
		if ( Best != None )
			F.ServerSetTarget(Best);
		F.bTargetClosestToCrosshair = false;
	}

	T = F.CurrentTarget;
	if ( T == None || T.Health < 1 || T.bDeleteMe )
		return;
	C.R = 64; C.G = 200; C.B = 64; C.A = 255;
	RS = LayerRes(PC, Tex);
	if ( !InView(PC, Tex, T.Location, Loc, Rot, PX, PY) )
	{
		DrawBehind(PC, H, Tex, T, false, Loc, Rot, PX, PY, C, RS);
		return;
	}
	// the box around the collision cylinder (x1.5, as UT), at least 16 px of a 640 wide screen
	for ( i = 0; i < 8; i++ )
	{
		Corner = T.Location;
		Corner.X += T.CollisionRadius * 1.5 * (2 * (i & 1) - 1);
		Corner.Y += T.CollisionRadius * 1.5 * (2 * ((i >> 1) & 1) - 1);
		Corner.Z += T.CollisionHeight * 1.5 * (2 * ((i >> 2) & 1) - 1);
		if ( !PC.HudProject(Tex, Corner, Loc, Rot, PX, PY) )
			continue;
		if ( !bAny || PX < X0 ) X0 = PX;
		if ( !bAny || PX > X1 ) X1 = PX;
		if ( !bAny || PY < Y0 ) Y0 = PY;
		if ( !bAny || PY > Y1 ) Y1 = PY;
		bAny = true;
	}
	if ( !bAny )
		return;
	BX = 16 * PC.LayerPixels(Tex) / 640;
	BY = BX;
	if ( X1 - X0 < BX ) { PX = (X0 + X1) * 0.5; X0 = PX - BX * 0.5; X1 = PX + BX * 0.5; }
	if ( Y1 - Y0 < BY ) { PY = (Y0 + Y1) * 0.5; Y0 = PY - BY * 0.5; Y1 = PY + BY * 0.5; }
	Tex.DrawTile(X0, Y0, BX, BY, 0, 0, 32, 32, Material'AS_FX_TX.Icons.InfoBracket_FB', C);
	Tex.DrawTile(X1 - BX, Y0, BX, BY, 0, 0, -32, 32, Material'AS_FX_TX.Icons.InfoBracket_FB', C);
	Tex.DrawTile(X0, Y1 - BY, BX, BY, 0, 0, 32, -32, Material'AS_FX_TX.Icons.InfoBracket_FB', C);
	Tex.DrawTile(X1 - BX, Y1 - BY, BX, BY, 0, 0, -32, -32, Material'AS_FX_TX.Icons.InfoBracket_FB', C);
}

// an Onslaught vehicle's / turret's crosshairs where its gun hits (traced from its muzzle along its own aim, so a
// gun that turns at a set rate shows where it really fires): UT's own crosshair (HudCDeathMatch.DrawCrosshair:
// your style, colour and scale) and the vehicle's "barrel aligned" one (its DrawHUD, while the gun is on target)
function DrawONSCrosshair(VRPlayerController PC, HudBase H, ScriptedTexture Tex, vector Loc, rotator Rot)
{
	local vector Start, Dir, HL;
	local ONSWeapon W;
	local byte bHit;
	local float PX, PY, RS, TW, TH, S;
	local int i;
	local Material M;
	local color C;
	local ONSVehicle OV;
	local ONSWeaponPawn WP;
	local bool bTraced, bSeen;

	bTraced = PC.VehicleAimTrace(Start, Dir, HL, W, bHit);
	bSeen = bTraced && InView(PC, Tex, HL, Loc, Rot, PX, PY);
	if ( PC.bDebugLog && PC.Level.TimeSeconds > NextAimLog )
	{
		NextAimLog = PC.Level.TimeSeconds + 1.0;
		Log("UT2004VR: ons crosshair "$PC.Pawn.Class.Name$" gun "$W$" traced "$bTraced$" in view "$bSeen$" at "$int(PX)$","$int(PY)$" of "$Tex.USize$" muzzle "$Start$" aim "$rotator(Dir)$" eyes "$PC.VRHeadWorld$" gaze "$PC.VRHeadRot$" hit "$bHit$" "$int(VSize(HL - Start))$" uu crosshair "$PC.myHUD.bCrosshairShow$" correct "$(W != None && W.bCorrectAim), 'UT2004VR');
	}
	if ( !bSeen )
		return;
	RS = LayerRes(PC, Tex);
	// UT's crosshair (HUD.CrosshairStyle from the player's settings; Settings' "show crosshair" is the active HUD's)
	if ( H != None && H.Crosshairs.Length > 0 && PC.myHUD.bCrosshairShow )
	{
		i = Clamp(H.CrosshairStyle, 0, H.Crosshairs.Length - 1);
		M = H.Crosshairs[i].WidgetTexture;
		if ( M != None )
		{
			TW = Abs(H.Crosshairs[i].TextureCoords.X2 - H.Crosshairs[i].TextureCoords.X1);
			TH = Abs(H.Crosshairs[i].TextureCoords.Y2 - H.Crosshairs[i].TextureCoords.Y1);
			S = H.Crosshairs[i].TextureScale * 0.5 * H.CrosshairScale * RS;
			C = H.CrosshairColor;
			Tex.DrawTile(PX - TW * S * 0.5, PY - TH * S * 0.5, TW * S, TH * S, H.Crosshairs[i].TextureCoords.X1,
				H.Crosshairs[i].TextureCoords.Y1, TW, TH, M, C);
		}
	}
	// the vehicle's own aim crosshair while the gun is on target
	OV = ONSVehicle(PC.Pawn);
	WP = ONSWeaponPawn(PC.Pawn);
	if ( W != None && W.bCorrectAim && OV != None && W.bShowAimCrosshair && OV.CrosshairTexture != None )
		AimTile(PC, Tex, PX, PY, OV.CrosshairTexture, OV.CrosshairX, OV.CrosshairY, OV.CrosshairColor);
	else if ( W != None && W.bCorrectAim && WP != None && WP.CrosshairTexture != None )
		AimTile(PC, Tex, PX, PY, WP.CrosshairTexture, WP.CrosshairX, WP.CrosshairY, WP.CrosshairColor);
}

// the space fighter's steering crosshair (gaze steering): UT's crosshair (your style, colour and scale) where the
// ship is heading for
function DrawSteerCrosshair(VRPlayerController PC, HudBase H, ScriptedTexture Tex, vector Loc, rotator Rot, vector P)
{
	local float PX, PY, TW, TH, S;
	local int i;
	local Material M;
	local color C;

	if ( H == None || H.Crosshairs.Length == 0 || !InView(PC, Tex, P, Loc, Rot, PX, PY) )
		return;
	i = Clamp(H.CrosshairStyle, 0, H.Crosshairs.Length - 1);
	M = H.Crosshairs[i].WidgetTexture;
	if ( M == None )
		return;
	TW = Abs(H.Crosshairs[i].TextureCoords.X2 - H.Crosshairs[i].TextureCoords.X1);
	TH = Abs(H.Crosshairs[i].TextureCoords.Y2 - H.Crosshairs[i].TextureCoords.Y1);
	S = H.Crosshairs[i].TextureScale * 0.5 * H.CrosshairScale * LayerRes(PC, Tex);
	C = H.CrosshairColor;
	Tex.DrawTile(PX - TW * S * 0.5, PY - TH * S * 0.5, TW * S, TH * S, H.Crosshairs[i].TextureCoords.X1,
		H.Crosshairs[i].TextureCoords.Y1, TW, TH, M, C);
}

// a tile CrosshairX/Y window pixels from the centre (scaled from the window to the layer in this eye)
function AimTile(VRPlayerController PC, ScriptedTexture Tex, float PX, float PY, Texture T, float CX, float CY, color C)
{
	local float K;
	K = PC.LayerPixels(Tex) / FMax(PC.WinW, 1);
	C.A = 255;
	Tex.DrawTile(PX - CX * K, PY - CY * K, (CX * 2 + 1) * K, (CY * 2 + 1) * K, 0, 0, T.USize, T.VSize, T, C);
}

// HUD_Assault.IsObjectiveVisible, from the head
function bool ObjectiveVisible(VRPlayerController PC, HUD_Assault H, GameObjective GO)
{
	local vector Dir, P;

	if ( !GO.bOverrideZoneCheck && PC.Pawn.Region.Zone != GO.Region.Zone )
		return false;
	if ( GO.DrawDistThresHold > 0 && VSize(GO.Location - PC.VRHeadWorld) > GO.DrawDistThresHold )
		return false;
	if ( GO.bOverrideVisibilityCheck )
		return true;
	Dir = GO.Location - PC.VRHeadWorld;
	Dir.Z = 0;
	P = GO.Location - 2.0 * GO.CollisionRadius * Normal(Dir);
	return PC.FastTrace(P, PC.VRHeadWorld);
}

// HUD_Assault.DrawVisibleObjective (without its appear/fade-out timing)
function DrawVisibleObjective(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, GameObjective GO, float PX, float PY,
	color ObjColor, byte bPulse, float Prog, float RS)
{
	local float T;
	local color C;

	C = ObjColor;
	if ( bPulse == 0 )
		C.A = 63 + 128 * H.fPulse;
	else
		C.A = 127;
	T = 64 * RS * H.ObjectiveScale * H.HUDScale;
	if ( GO.IsA('UseObjective') )
	{
		if ( GO.UseDescription != "" )
			Text(PC, H, Tex, PX, PY, H.IP_Bracket_Open @ GO.UseDescription @ H.IP_Bracket_Close, C);
	}
	else if ( GO.ObjectiveTypeIcon != None )
		Tex.DrawTile(PX - T * 0.5, PY - T * 0.5, T, T, 0, 0, 64, 64, GO.ObjectiveTypeIcon, C);

	// the defenders' shield
	if ( H.ASGRI != None && H.ASGRI.IsDefender(PC.Pawn.GetTeamNum()) )
	{
		if ( GO.IsCritical() )
			C = Blend(H.GreenColor, H.GoldColor, H.fPulse);
		else
			C = H.GreenColor;
		if ( bPulse == 0 )
			C.A = 63 + 128 * H.fPulse;
		else
			C.A = 127;
		T = 1.25 * 64 * RS * H.ObjectiveScale * H.HUDScale;
		Tex.DrawTile(PX - T * 0.5, PY - T * 0.5, T, T, 191, 191, 64, 64, Texture'AS_FX_TX.HUD.OBJ_Status', C);
	}
	if ( Prog > 0 )
		DrawHealthBar(H, Tex, PX, PY - 48 * RS, Prog, ObjColor, RS);
}

// A * t + B * (1 - t) (the HUD classes' colour operators aren't visible outside them)
static function color Blend(color A, color B, float T)
{
	local color C;
	C.R = byte(A.R * T + B.R * (1 - T));
	C.G = byte(A.G * T + B.G * (1 - T));
	C.B = byte(A.B * T + B.B * (1 - T));
	C.A = byte(A.A * T + B.A * (1 - T));
	return C;
}

// HUD_Assault.DrawHealthBar
function DrawHealthBar(HUD_Assault H, ScriptedTexture Tex, float X, float Y, float Pct, color C, float RS)
{
	local float W, Ht;
	local color B;

	W = H.default.HealthBarWidth * RS * H.HUDScale;
	Ht = H.default.HealthBarHeight * RS * H.HUDScale;
	Tex.DrawTile(X - W * 0.5, Y - Ht * 0.5, W, Ht, 0, 0, H.HealthBarBackMat.MaterialUSize(), H.HealthBarBackMat.MaterialVSize(),
		H.HealthBarBackMat, C);
	B = class'HUD_Assault'.static.GetGYRColorRamp(Pct);
	B.A = 200;
	Tex.DrawTile(X - W * 0.49, Y - Ht * 0.3, W * Pct * 0.98, Ht * 0.6, 0, 0, H.HealthBarMat.MaterialUSize(), H.HealthBarMat.MaterialVSize(),
		H.HealthBarMat, B);
}

// HUD_Assault.DrawObjectiveStatusOverlay: the ring that fills green -> yellow -> red
function DrawStatusOverlay(HUD_Assault H, ScriptedTexture Tex, float X, float Y, float Prog, float Scale, float RS)
{
	local float S, U, V;
	local color C;

	if ( Prog <= 0 )
		return;
	S = 64 * 0.5 * H.HUDScale * Scale * RS;
	C = class'HUD_Assault'.static.GetGYRColorRamp(Prog);
	C.A = 128;
	if ( Prog > 0.6 )
	{
		U = 64 * (10 - Ceil(Prog * 10));
		V = 0;
	}
	else if ( Prog > 0.2 )
	{
		U = 64 * (6 - Ceil(Prog * 10));
		V = 64;
	}
	else
	{
		U = 64 * (2 - Ceil(Prog * 10));
		V = 128;
	}
	Tex.DrawTile(X - S * 0.5, Y - S * 0.5, S, S, U, V, 64, 64, Texture'AS_FX_TX.HUD.OBJ_Status', C);
}

function DrawCriticalOverlay(HUD_Assault H, ScriptedTexture Tex, float X, float Y, float Scale, float RS)
{
	local float SX, SY;
	SX = 24 * 0.33 * H.HUDScale * Scale * RS;
	SY = 62 * 0.33 * H.HUDScale * Scale * RS;
	Tex.DrawTile(X - SX * 0.5, Y - SY * 0.5, SX, SY, 344, 210, 20, 62, FinalBlend'HudContent.Generic.HUDPulse', H.WhiteColor);
}

// HUD_Assault.DrawActorTracking_Obstructed: a small objective icon with the distance under it; PY moves to the icon
function DrawObstructed(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, Actor A, bool bOptional, out float PX, out float PY,
	color C, float RS)
{
	local float T;

	T = 64 * 0.45 * RS * H.ObjectiveScale * H.HUDScale;
	if ( bOptional )
		Tex.DrawTile(PX - T * 0.5, PY - T, T, T, 191, 127, 64, 64, Texture'AS_FX_TX.HUD.OBJ_Status', C);
	else
		Tex.DrawTile(PX - T * 0.5, PY - T, T, T, 127, 127, 64, 64, Texture'AS_FX_TX.HUD.OBJ_Status', C);
	Text(PC, H, Tex, PX, PY + T * 0.1, H.IP_Bracket_Open $ int(VSize(A.Location - PC.VRHeadWorld) * 0.01875) $ H.MetersString
		$ H.IP_Bracket_Close, C);
	PY -= T * 0.5;
}

// HUD_Assault.DrawActorTracking_Behind: an arrow at the edge of the HUD layer, toward the target
function DrawBehind(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, Actor A, bool bOptional, vector Loc, rotator Rot,
	out float PX, out float PY, color C, float RS)
{
	local vector L;
	local float DY, DZ, D, Edge, T;
	local TexRotator Arrow;

	// the direction in the head's view plane, out to the layer's edge (a box, like the original's screen edge)
	L = (A.Location - PC.VRHeadWorld) << PC.VRHeadRot;
	DY = L.Y;
	DZ = L.Z;
	D = Sqrt(DY * DY + DZ * DZ);
	if ( D < 1 )
		return;
	DY /= D;
	DZ /= D;
	if ( Abs(DY) * PC.LayerHalfUp() > Abs(DZ) * PC.LayerHalfRight() )
		Edge = PC.LayerHalfRight() / Abs(DY);
	else
		Edge = PC.LayerHalfUp() / Abs(DZ);
	Edge *= 0.92;   // the arrow inside the edge
	if ( !PC.LayerPoint(Tex, Loc, Rot, DY * Edge, DZ * Edge, PX, PY) )
		return;

	if ( ArrowCount >= ArrayCount(Arrows) )
		return;
	if ( Arrows[ArrowCount] == None )
	{
		Arrows[ArrowCount] = new(None) class'TexRotator';
		Arrows[ArrowCount].UOffset = 64;
		Arrows[ArrowCount].VOffset = 64;
	}
	Arrow = Arrows[ArrowCount++];
	Arrow.Rotation.Yaw = Atan(DZ, DY) * 32768 / 3.14159265;
	if ( bOptional )
		Arrow.Material = Texture'AS_FX_TX.HUD.Objective_Optional_Indicator';
	else
		Arrow.Material = Texture'AS_FX_TX.HUD.Objective_Primary_Indicator';
	T = 128 * 0.45 * RS * H.ObjectiveScale * H.HUDScale;
	Tex.DrawTile(PX - T * 0.5, PY - T * 0.5, T, T, 0, 0, 128, 128, Arrow, C);
}

// HUD_Assault.DrawActorTracking: true when an icon should go at PX, PY (out of view or blocked)
function bool DrawTracking(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, Actor A, vector Loc, rotator Rot,
	out float PX, out float PY, color C, float RS)
{
	local float Prog;

	if ( Pawn(A) != None && Pawn(A).HealthMax > 0 )
		Prog = float(Pawn(A).Health) / Pawn(A).HealthMax;
	if ( !InView(PC, Tex, A.Location, Loc, Rot, PX, PY) )
	{
		DrawBehind(PC, H, Tex, A, false, Loc, Rot, PX, PY, C, RS);
		if ( Prog > 0 )
			DrawStatusOverlay(H, Tex, PX, PY, Prog, H.ObjectiveScale * 0.67, RS);
		return true;
	}
	if ( VSize(A.Location - PC.VRHeadWorld) > 2048 || !PC.FastTrace(A.Location, PC.VRHeadWorld) )
	{
		DrawObstructed(PC, H, Tex, A, false, PX, PY, C, RS);
		if ( Prog > 0 )
			DrawStatusOverlay(H, Tex, PX, PY, Prog, H.ObjectiveScale * 0.67, RS);
		return true;
	}
	if ( Prog > 0 )
		DrawHealthBar(H, Tex, PX, PY - 48 * RS, Prog, C, RS);
	return false;
}

function DrawVehicleIcon(HUD_Assault H, ScriptedTexture Tex, Vehicle V, float X, float Y, float RS)
{
	local float S, SX, SY, Ratio;
	local color C;

	if ( V.VehicleIcon.Material == None || V.VehicleIcon.SizeY == 0 )
		return;
	S = H.ObjectiveScale * H.HUDScale;
	Ratio = V.VehicleIcon.SizeX / V.VehicleIcon.SizeY;
	SX = 32 * S * RS;
	SY = (32 / Ratio) * S * RS;
	if ( V.VehicleIcon.bIsGreyScale )
		C = class'HUD_Assault'.static.GetTeamColor(1 - V.Team);
	else
		C = H.WhiteColor;
	C.A = 127 + 128 * H.fPulse;
	Tex.DrawTile(X - SX * 0.5, Y - SY * 0.5, SX, SY, V.VehicleIcon.X, V.VehicleIcon.Y, V.VehicleIcon.SizeX, V.VehicleIcon.SizeY,
		V.VehicleIcon.Material, C);
}

// centred text in the HUD's console font for the layer's size
function Text(VRPlayerController PC, HUD_Assault H, ScriptedTexture Tex, float X, float Y, string S, color C)
{
	local Font F;
	local int W, Ht;

	F = H.LoadFont(Clamp(H.ConsoleFontSize + 6 - PC.MsgFontSteps(PC.LayerPixels(Tex)), 0, 8));
	if ( F == None )
		return;
	Tex.TextSize(S, F, W, Ht);
	PC.MsgText(Tex, X - W / 2, Y, S, F, C);
}
