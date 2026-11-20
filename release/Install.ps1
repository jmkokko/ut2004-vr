# UT2004VR installer: copies the mod into an OldUnreal UT2004 (patch 3374, 64-bit) install.
# Run through Install.bat. Changes nothing outside the game's System folder (and, if you agree, a desktop shortcut).
param([string]$GameDir = "", [switch]$Unattended, [switch]$NoShortcut)   # -Unattended: take every default answer

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Payload = Join-Path $Root "System"
$MinBuild = "2026-07-18"   # OldUnreal 3374 Preview 23: older builds crash in Assault at round start

function Say($t) { Write-Host $t }
function Ask($q, $def) {
    if ($Unattended) { return $def }
    $a = Read-Host "$q [$(if ($def) {'Y/n'} else {'y/N'})]"
    if ($a -eq "") { return $def }
    return $a -match '^[Yy]'
}
function Fail($t) { Write-Host ""; Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }

Say "UT2004VR installer"
Say "=================="
if (-not (Test-Path (Join-Path $Payload "UT2004VR.u"))) { Fail "Run Install.bat from the unzipped UT2004VR folder (System\UT2004VR.u is missing)." }

# --- find the game ---
function IsGame($d) { return $d -and (Test-Path (Join-Path $d "System\UT2004.exe")) }
if (-not $GameDir) {
    foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Unreal Technology\Installed Apps\UT2004",
                     "HKLM:\SOFTWARE\Unreal Technology\Installed Apps\UT2004")) {
        $p = Get-ItemProperty -Path $k -Name Folder -ErrorAction SilentlyContinue
        if ($p -and (IsGame $p.Folder)) { $GameDir = $p.Folder; break }
    }
    if ($GameDir) {
        Say "Found UT2004 in: $GameDir"
        if (-not (Ask "Install UT2004VR there?" $true)) { $GameDir = "" }
    }
    while (-not (IsGame $GameDir)) {
        $GameDir = (Read-Host "UT2004 folder (the one that contains System\UT2004.exe)").Trim('"', ' ')
        if (-not (IsGame $GameDir)) { Say "  No System\UT2004.exe there." }
    }
}
if (-not (IsGame $GameDir)) { Fail "No System\UT2004.exe in $GameDir" }
$Sys = Join-Path $GameDir "System"

# --- check the game version: 64-bit, OldUnreal 3374, recent enough ---
$exe = [System.IO.File]::ReadAllBytes((Join-Path $Sys "UT2004.exe"))
$pe = [BitConverter]::ToInt32($exe, 0x3C)
$machine = [BitConverter]::ToUInt16($exe, $pe + 4)
if ($machine -ne 0x8664) {
    Fail "This UT2004 is 32-bit. UT2004VR needs OldUnreal's patch 3374 (64-bit): https://github.com/OldUnreal/UT2004Patches/releases"
}
$label = ""
$bi = Join-Path $Sys "Build.ini"
if (Test-Path $bi) { $label = (Get-Content $bi | Where-Object { $_ -match '^Label=' }) -replace '^Label=', '' }
Say "Game build: $label"
if ($label -notmatch 'v3374') {
    Fail "This is not OldUnreal patch 3374. Install it first: https://github.com/OldUnreal/UT2004Patches/releases"
}
if ($label -match '\[(\d{4}-\d{2}-\d{2})') {
    if ($Matches[1] -lt $MinBuild) {
        Say ""
        Say "This 3374 build ($($Matches[1])) is older than Preview 23 ($MinBuild). Assault crashes at round start on it."
        Say "Update to OldUnreal's latest patch: https://github.com/OldUnreal/UT2004Patches/releases"
        if (-not (Ask "Install anyway?" $false)) { exit 1 }
    }
}

# --- the game must not be running ---
if (Get-Process UT2004, UCC -ErrorAction SilentlyContinue) { Fail "UT2004 is running. Quit it and run Install.bat again." }

# --- another d3d9.dll (ReShade, dgVoodoo...) ---
$d3d9 = Join-Path $Sys "d3d9.dll"
$backup = Join-Path $Sys "d3d9.dll.pre-UT2004VR"
if (Test-Path $d3d9) {
    $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($d3d9))
    if (-not $txt.Contains("UT2004VR proxy")) {
        Say ""
        Say "System\d3d9.dll belongs to another program (ReShade, dgVoodoo or similar). UT2004VR needs that file name."
        Say "It will be kept as d3d9.dll.pre-UT2004VR and put back by the uninstaller; until then that program is off."
        if (-not (Ask "Continue?" $false)) { exit 1 }
        if (-not (Test-Path $backup)) { Copy-Item $d3d9 $backup }
    }
}

# --- copy ---
$installed = New-Object System.Collections.Generic.List[string]
$kept = @()
Get-ChildItem -Path $Payload -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Payload.Length + 1)
    $dst = Join-Path $Sys $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    if ($rel -eq "UT2004VR_proxy.ini" -and (Test-Path $dst)) {
        $kept += $rel   # your settings from an earlier install stay
    } else {
        Copy-Item -Force $_.FullName $dst
    }
    $installed.Add($rel)
}
$installed.Add("UT2004VR-files.txt")
[System.IO.File]::WriteAllLines((Join-Path $Sys "UT2004VR-files.txt"), $installed)
Say ""
Say "Installed $($installed.Count - 1) files into $Sys"
foreach ($k in $kept) { Say "  kept your existing $k" }

# --- shortcut ---
if (-not $NoShortcut -and (Ask "Create a desktop shortcut 'UT2004 VR'?" $true)) {
    $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "UT2004 VR.lnk"
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = Join-Path $Sys "Play-VR.bat"
    $s.WorkingDirectory = $Sys
    $s.IconLocation = (Join-Path $Sys "UT2004.exe") + ",0"
    $s.Description = "Unreal Tournament 2004 in VR (UT2004VR)"
    $s.Save()
    Say "  $lnk"
}

Say ""
Say "Done. To play in VR:"
Say "  1. Start SteamVR with your headset and controllers on."
Say "  2. Run 'UT2004 VR' (or System\Play-VR.bat)."
Say "Starting UT2004 the normal way still gives the plain, flat game."
Say "To remove UT2004VR: System\UT2004VR-Uninstall.bat"
