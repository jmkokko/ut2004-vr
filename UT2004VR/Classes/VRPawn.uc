//=============================================================================
// VRPawn: shots come out of the gun in your hand, not your eyes.
// Every UT2004 weapon starts its trace/projectile at Location + EyePosition() and its
// beam/flash effects at Location + CalcDrawOffset() + EffectOffset, so pointing those at
// the tracked right hand moves hitscan, projectiles and beams to the weapon.
//=============================================================================
class VRPawn extends xPawn;

simulated function vector EyePosition()
{
	local VRPlayerController PC;
	local vector Muzzle;

	PC = VRPlayerController(Controller);
	if ( PC != None && PC.GetMuzzle(Muzzle) )
		return Muzzle - Location;
	return Super.EyePosition();
}

// Weapon.GetEffectStart() = Location + CalcDrawOffset(W) + EffectOffset (in view axes): cancel the
// screen-space EffectOffset so beams start exactly at the muzzle
simulated function vector CalcDrawOffset(inventory Inv)
{
	local VRPlayerController PC;
	local vector Muzzle, X, Y, Z, Ofs;
	local Weapon W;

	PC = VRPlayerController(Controller);
	if ( PC == None || !PC.GetMuzzle(Muzzle) )
		return Super.CalcDrawOffset(Inv);
	W = Weapon(Inv);
	if ( W != None )
	{
		GetAxes(PC.Rotation, X, Y, Z);
		if ( class'PlayerController'.Default.bSmallWeapons )
			Ofs = W.SmallEffectOffset;
		else
			Ofs = W.EffectOffset;
		// the Mine Layer's guide beam and the (Ion/target) Painter's beam, their only users of CalcDrawOffset, add the
		// beam's own offset, not the gun's (it put them ~100 uu behind the muzzle, the guide beam also 40 uu up)
		if ( W.IsA('ONSMineLayer') )
			Ofs = class'ONSMineLayerTargetBeamEffect'.default.EffectOffset;
		else if ( W.IsA('Painter') )
			Ofs = class'PainterBeamEffect'.default.EffectOffset;
		Muzzle = Muzzle - (Ofs.X * X + Ofs.Y * Y * W.Hand + Ofs.Z * Z);
		// LinkGun.GetEffectStart (Hand 0) lowers its offset by 14 (10 on the old mesh) and adds 3 sideways,
		// and LinkBeamEffect then starts 60 uu behind that: undo both so the alt-fire beam leaves the muzzle
		if ( W.IsA('LinkGun') && W.Hand == 0 )
		{
			if ( W.bUseOldWeaponMesh )
				Muzzle += 10 * Z;
			else
				Muzzle += 14 * Z;
			Muzzle += -3 * Y + 60 * X;
		}
		return Muzzle - Location;
	}
	return Muzzle - Location;
}

defaultproperties
{
}
