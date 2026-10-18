//=============================================================================
// VRLaser: a thin aiming laser from the muzzle along the barrel (the Ion Painter's
// beam texture, tinted red, no sound). Start = Location, end = mSpawnVecA.
//=============================================================================
class VRLaser extends xEmitter;

#exec OBJ LOAD FILE=XEffectMat.utx

defaultproperties
{
	mParticleType=PT_Beam
	mMaxParticles=3
	mRegenDist=100.000000
	mSizeRange(0)=0.600000
	mSizeRange(1)=0.600000
	mColorRange(0)=(R=140,G=20,B=20)
	mColorRange(1)=(R=140,G=20,B=20)
	mAttenuate=False
	mAttenKa=1.000000
	Skins(0)=Texture'XEffectMat.Ion.painter_beam'
	Style=STY_Additive
	bNetTemporary=False
	RemoteRole=ROLE_None
	bHidden=true
}
