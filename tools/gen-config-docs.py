#!/usr/bin/env python3
"""Write docs/CONFIGURATION.md from the source: every `var config` setting of the UnrealScript classes (name, default
from defaultproperties, the comment on its declaration) grouped by topic, plus the proxy's UT2004VR_proxy.ini keys.

Run after changing a setting: python3 tools/gen-config-docs.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLASSES = ROOT / "UT2004VR" / "Classes"

# topic -> settings of VRPlayerController ([UT2004VR.VRPlayerController] in UT2004VR.ini); anything not listed lands
# in "Other"
GROUPS = [
    ("Movement and turning", "bHandRelativeMove bGazeHeading HeadingTurnRate bSteerByGaze SteerGain SteerDeadzone "
     "SteerMaxDegPerSec ChairHistLife bSmoothTurn SnapTurnDegrees SmoothTurnDegPerSec MoveSpeedScale bTeleport "
     "TeleportSpeed TeleportMaxDist CrouchHeadMeters bVignette bJumpOnStickClick"),
    ("Height and world scale", "UUPerMeter bAutoHeight StandEyeMeters bMatchGameHeight EyeHeightBonus "
     "bSeatedAutoLevel AutoLevelSeconds NeckModelMode NeckForward NeckUp NeckBlendTime"),
    ("Weapons, laser and recoil", "bWeapons GunOffset GunPitchOffset FlipGuns GunScale MuzzleForward bLaser "
     "LaserRange LaserDotDeg LaserBrightness LaserWidth LaserFadeIn RecoilScale RecoilReturn"),
    ("Keyboard and mouse mode", "bKeyboardMouse KBMGunOffset KBMChestBelowEyes GunLagTime GunLagMax GunLagSmooth"),
    ("Scope (zoom)", "bScope ScopeDiameter ScopeOffset ScopeKBMDiameter ScopeKBMDistance ScopeMinZoom ScopeRes "
     "ScopeStickZoom"),
    ("Guided Redeemer", "RedeemerSteer bRedeemerRoll bRedeemerWindow RedeemerWindowDeg RedeemerWindowDist"),
    ("Vehicles and turrets", "VehicleTurnDegPerSec bVehicleHandAim TurretEdgeDeg TurretEdgeTurn "
     "TurretEdgeMaxDegPerSec VehicleBehindPitch VehicleBehindScale GazeSteerFollow TurretSpeed InstantTurretSpeed "
     "bVehicleLaser ASTurretFollow"),
    ("Assault space fighters", "bFighterGazeSteer FighterGazeGain FighterBankPerDeg FighterMaxBank FighterInertia "
     "FighterSteer"),
    ("Behind view", "BehindDistance BehindHeight BehindRight"),
    ("HUD, messages and scoreboard", "bVRHud HudDistance HudSpread HudTopUp HudSize HudLower HudBottomUp "
     "bVROriginalHud OriginalHudScale bVRScoreboardOriginal ScoresWidthDeg bVRClock bVRMessages VRMessageFontBoost"),
    ("Desktop window", "bMirrorFitHud MirrorHudMargin"),
    ("Debugging", "bDebugLog TestExec bCalib bCalibGun"),
]

# UT2004VR_proxy.ini, [VR] (read by the d3d9 proxy)
PROXY = [
    ("RenderScale", "0.85", "Eye resolution as a fraction of SteamVR's recommended size. Lower it if the frame rate drops."),
    ("GPUShare", "1", "1: run the game on D3D9Ex and hand the eye images to SteamVR on the GPU (fast). 0: CPU copy (slow fallback)."),
    ("Port", "7790", "Local UDP port for poses from the proxy to the game; the game's `[UT2004VR.VRLink] VRPort` must match."),
    ("MirrorEye", "0", "Desktop window: 0 left eye, 1 right eye, -1 a plain mono view."),
    ("MirrorFill", "1", "1: crop the eye to fill the window. 0: letterbox the whole eye view."),
    ("MirrorZoom", "1.08", "Above 1 widens the mirror slightly past the lens edge."),
    ("PanelDistance", "0.95", "Menu panel distance (m)."),
    ("PanelWidth", "1.6", "Menu panel width (m)."),
    ("PanelCurvature", "0.6", "0 flat, 1 a cylinder centred on your head."),
    ("PanelFollowDeg", "0", "Main menus: look this far away for 1.5 s and the panel comes back in front of you (0 off)."),
    ("ScoreboardDistance", "1.0", "Scoreboard panel distance (m), when it has its own panel (bVROriginalHud off)."),
    ("ScoreboardWidth", "1.5", "Scoreboard panel width (m)."),
    ("SpectatorBarDistance", "1.0", "UT's spectator bar: distance (m)."),
    ("SpectatorBarWidth", "1.3", "... width (m)."),
    ("SpectatorBarDrop", "0.3", "... how far below eye level (m)."),
    ("ScreenDistance", "2.4", "Online (no VR on the server): the flat game on a big screen this far away (m)."),
    ("ScreenWidth", "3.2", "... and this wide (m)."),
    ("LeftHanded", "0", "Written by the game from Settings > Player > Weapon Hand (controller mode). Don't edit."),
    ("Mock, MockDemo, DumpEyes, DumpEyesStart, DumpEyesStep", "0", "Developer tests: a simulated headset and eye image dumps (see DEVELOPMENT.md)."),
]


def settings(cls):
    src = (CLASSES / f"{cls}.uc").read_text(encoding="latin-1")
    body, _, dp = src.partition("defaultproperties")
    defaults = {}
    for line in dp.splitlines():
        m = re.match(r"\s*(\w+)(\(\d+\))?=(.*)$", line)
        if m and not m.group(2):
            defaults[m.group(1)] = m.group(3).strip()
        elif m:
            defaults.setdefault(m.group(1), "(list)")
    out = {}
    for line in body.splitlines():
        m = re.match(r"\s*var\s+(?:globalconfig|config)\s+([\w<>\.]+(?:<[\w\.]+>)?)\s+([^;]+);\s*(?://\s*(.*))?", line)
        if not m:
            continue
        typ, names, comment = m.group(1), m.group(2), (m.group(3) or "").strip()
        comment = re.split(r"\s{3,}//", comment)[0]   # a second comment trailing on the same line
        for n in [x.strip() for x in names.split(",")]:
            n = re.sub(r"\[.*\]", "", n)
            out[n] = (typ, defaults.get(n, ""), comment)
    return out


def tidy(v):
    v = v.replace('"', "")
    return re.sub(r"(\d+\.\d*?)0+\b", lambda m: m.group(1).rstrip("."), v) if v else "-"


def table(rows):
    lines = ["| Setting | Default | What it does |", "|---|---|---|"]
    for name, default, text in rows:
        text = text.replace("|", "\\|").replace("<", "&lt;").replace(">", "&gt;")
        lines.append(f"| `{name}` | {('`' + default + '`') if default not in ('', '-') else '-'} | {text} |")
    return "\n".join(lines)


def main():
    pc = settings("VRPlayerController")
    tuning = settings("VRTuning")
    out = ["# UT2004VR configuration",
           "",
           "<!-- Generated by tools/gen-config-docs.py from the source; edit the comments in the classes, then re-run. -->",
           "",
           "Most players never need this page: the defaults are tuned, and the console commands in the README cover",
           "the usual adjustments. Everything here can still be changed.",
           "",
           "**Where settings live** (all in the game's `System` folder):",
           "- `UT2004VR.ini`: the mod's settings, created on first run. Sections `[UT2004VR.VRPlayerController]`,",
           "  `[UT2004VR.VRTuning]` (what the tuning commands save: grips, scopes, seats...) and `[UT2004VR.VRGame]`.",
           "- `UT2004VR_proxy.ini`: the d3d9 proxy (resolution, panels, desktop mirror).",
           "- `UT2004VR_Game.ini`: the game's own settings for VR launches (made by `Play-VR.bat` from `UT2004.ini`).",
           "",
           "Change a setting while the game is closed, or from the console with",
           "`set UT2004VR.VRPlayerController <Setting> <value>` (saved at once). Values in uu are Unreal units:",
           "52.5 uu is about 1 m.",
           ""]
    used = set()
    for title, names in GROUPS:
        rows = []
        for n in names.split():
            if n in pc:
                typ, d, c = pc[n]
                if n in tuning and tuning[n][1]:
                    d = tuning[n][1]   # VRTuning's saved value wins when bSaved
                rows.append((n, tidy(d), c))
                used.add(n)
        if rows:
            out += [f"## {title}", "", table(rows), ""]
    rest = [(n, tidy(d), c) for n, (t, d, c) in pc.items() if n not in used]
    if rest:
        out += ["## Other", "", table(rest), ""]
    out += ["## Saved tuning (`[UT2004VR.VRTuning]`)", "",
            "Written by the tuning console commands; the defaults are the author's play-tested set.", "",
            table([("Grips", "(list)", "Per-weapon handle offset in controller mode: `VRGrip <forward> <right> <up>` (uu), `VRGripReset`."),
                   ("KBMGrips", "(list)", "The same for keyboard mode."),
                   ("Scopes", "(list)", "Per-weapon scope lens position: `VRScope <forward> <right> <up> [diameter]` (m), `VRScopeReset`."),
                   ("VehSeats", "(list)", "Per-vehicle seat offset and model visibility: `VRSeat <forward> <right> <up>` (uu), `VRSeatMesh`."),
                   ("FlipGuns", "-", "Weapons whose model is upside down: `VRGunFlip`.")]), ""]
    game = settings("VRGame")
    out += ["## The VR deathmatch (`[UT2004VR.VRGame]`)", "",
            "Used by `Play-VR.bat <MapName>`; games started from the menus use the menus' own settings.", "",
            table([(n, tidy(d), c) for n, (t, d, c) in game.items()]), ""]
    out += ["## Proxy (`UT2004VR_proxy.ini`, section `[VR]`)", "",
            table([(k, d, t) for k, d, t in PROXY]), ""]
    (ROOT / "docs" / "CONFIGURATION.md").write_text("\n".join(out), encoding="utf-8")
    print("docs/CONFIGURATION.md:", len(pc) + len(game), "settings")


if __name__ == "__main__":
    main()
