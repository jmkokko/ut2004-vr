# UT2004VR uninstaller: removes the files Install.bat put into this System folder (listed in UT2004VR-files.txt),
# puts back a d3d9.dll it had set aside, and - if you want - your VR settings and the desktop shortcut.
param([switch]$Unattended)   # take every default answer (remove the mod, keep your settings)
$ErrorActionPreference = "Stop"
$Sys = $PSScriptRoot
function Ask($q, $def) {
    if ($Unattended) { return $def }
    $a = Read-Host "$q [$(if ($def) {'Y/n'} else {'y/N'})]"
    if ($a -eq "") { return $def }
    return $a -match '^[Yy]'
}

Write-Host "UT2004VR uninstaller ($Sys)"
if (Get-Process UT2004, UCC -ErrorAction SilentlyContinue) { Write-Host "UT2004 is running. Quit it first."; exit 1 }
$list = Join-Path $Sys "UT2004VR-files.txt"
if (-not (Test-Path $list)) { Write-Host "UT2004VR-files.txt is missing: nothing to remove."; exit 1 }
if (-not (Ask "Remove UT2004VR?" $true)) { exit 1 }

$self = @("UT2004VR-Uninstall.ps1", "UT2004VR-Uninstall.bat")
$settings = @("UT2004VR_proxy.ini")
foreach ($rel in Get-Content $list) {
    if ($self -contains $rel -or $settings -contains $rel -or $rel -eq "UT2004VR-files.txt") { continue }
    $p = Join-Path $Sys $rel
    if (Test-Path $p) { Remove-Item -Force $p }
}
$dir = Join-Path $Sys "UT2004VR"
if ((Test-Path $dir) -and -not (Get-ChildItem $dir)) { Remove-Item $dir }
$backup = Join-Path $Sys "d3d9.dll.pre-UT2004VR"
if (Test-Path $backup) {
    Move-Item -Force $backup (Join-Path $Sys "d3d9.dll")
    Write-Host "Put back the d3d9.dll that was there before UT2004VR."
}

# your VR settings and logs: kept unless you say otherwise (a reinstall picks them up again)
$mine = @("UT2004VR_Game.ini", "UT2004VR.ini", "UT2004VR_proxy.ini", "UT2004VR_proxy.log") | Where-Object { Test-Path (Join-Path $Sys $_) }
if ($mine.Count -gt 0 -and (Ask "Also delete your VR settings ($($mine -join ', '))?" $false)) {
    foreach ($f in $mine) { Remove-Item -Force (Join-Path $Sys $f) }
}
$lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "UT2004 VR.lnk"
if (Test-Path $lnk) { Remove-Item -Force $lnk }
Remove-Item -Force $list
Write-Host "UT2004VR removed. UT2004 itself is unchanged."
