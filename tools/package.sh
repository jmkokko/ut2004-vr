#!/usr/bin/env bash
# Build a release zip: dist/UT2004VR-<version>.zip
#
# UT2004VR.u is compiled against BUILDGAME (default C:\UT2004-Clean: a never-started OldUnreal 3374 install with the
# patch players get today) through a temporary ini, so nothing in that install changes; every file the build adds
# there is removed again. d3d9.dll comes from build-proxy.sh (MSVC, x64, static CRT).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(grep -o 'Version="[^"]*"' "$HERE/UT2004VR/Classes/VRMutator.uc" | cut -d'"' -f2)
PVER=$(grep -o 'define UT2004VR_VERSION "[^"]*"' "$HERE/proxy/d3d9proxy.cpp" | cut -d'"' -f2)
[ "$VERSION" = "$PVER" ] || { echo "version mismatch: VRMutator $VERSION, proxy $PVER"; exit 1; }
BUILDGAME=${BUILDGAME:-/mnt/c/UT2004-Clean}
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
R=$($PS -NoProfile -Command "(Get-Process UT2004,ucc -ErrorAction SilentlyContinue).Id" 2>&1 | tr -d '\r' | head -1)
[ -z "$R" ] || { echo "UT2004 or UCC is running - abort"; exit 1; }
[ ! -e "$BUILDGAME/System/UT2004VR.u" ] || { echo "$BUILDGAME already has UT2004VR.u (installed?) - use a clean install"; exit 1; }
echo "UT2004VR $VERSION, compiled against $(grep -a Label "$BUILDGAME/System/Build.ini" | tr -d '\r')"

# 1. UnrealScript, against the build install, through UT2004VR_Build.ini (Default.ini + EditPackages=UT2004VR)
cleanup() { rm -rf "$BUILDGAME/UT2004VR" "$BUILDGAME/System/UT2004VR_Build.ini" "$BUILDGAME/System/UT2004VR.u" \
  "$BUILDGAME/System/UT2004VR.ucl" "$BUILDGAME/System/UCC.log" "$BUILDGAME/System/UT2004VR_Build-User.ini"; }
trap cleanup EXIT
cp -r "$HERE/UT2004VR" "$BUILDGAME/UT2004VR"
sed 's/^\(EditPackages=AssaultBP\)\r\?$/\1\r\nEditPackages=UT2004VR\r/' "$BUILDGAME/System/Default.ini" > "$BUILDGAME/System/UT2004VR_Build.ini"
grep -q '^EditPackages=UT2004VR' "$BUILDGAME/System/UT2004VR_Build.ini" || { echo "no EditPackages=AssaultBP line"; exit 1; }
(cd "$BUILDGAME/System" && ./UCC.exe make -silent -ini=UT2004VR_Build.ini -userini=UT2004VR_Build-User.ini 2>&1 | tr -d '\r' | grep -a -E "rror|arning|Success" | tail -5)
[ -f "$BUILDGAME/System/UT2004VR.u" ] || { echo "UT2004VR.u was not built"; exit 1; }

# 2. the proxy
"$HERE/build-proxy.sh" >/dev/null
P=/mnt/c/ut2004vr-build/build/d3d9.dll
grep -a -q "UT2004VR proxy" "$P" || { echo "d3d9.dll has no version string"; exit 1; }

# 3. the release folder
DIST="$HERE/dist"; NAME="UT2004VR-$VERSION"; S="$DIST/$NAME"
rm -rf "$S" "$DIST/$NAME.zip"; mkdir -p "$S/System/UT2004VR" "$S/Installer"
cp "$BUILDGAME/System/UT2004VR.u" "$BUILDGAME/System/UT2004VR.ucl" "$S/System/"
cp "$P" "$S/System/d3d9.dll"
cp "$HERE/third_party/openvr/bin/win64/openvr_api.dll" "$S/System/"
cp "$HERE"/proxy/actions/*.json "$S/System/UT2004VR/"
cp "$HERE/proxy/UT2004VR_proxy.ini" "$S/System/"
cp "$HERE/Play-VR.bat" "$S/System/"
cp "$HERE/release/Install.bat" "$S/"
cp "$HERE/release/Install.ps1" "$S/Installer/"
cp "$HERE/release/UT2004VR-Uninstall.bat" "$HERE/release/UT2004VR-Uninstall.ps1" "$S/System/"
sed "s/@VERSION@/$VERSION/g" "$HERE/release/README.txt" > "$S/README.txt"
cp "$HERE/LICENSE" "$S/LICENSE.txt"
cp "$HERE/third_party/openvr/LICENSE" "$S/OpenVR-LICENSE.txt"
# Windows line endings for everything a player opens or runs
for f in "$S"/*.txt "$S"/*.bat "$S"/Installer/*.ps1 "$S"/System/*.bat "$S"/System/*.ps1 "$S"/System/*.ini; do
  sed -i 's/\r\?$/\r/' "$f"
done
(cd "$S" && find . -type f | sed 's|^\./||' | sort > "$DIST/$NAME.files")
(cd "$DIST" && rm -f "$NAME.zip" && python3 -I -c "
import os,sys,zipfile
name=sys.argv[1]
with zipfile.ZipFile(name+'.zip','w',zipfile.ZIP_DEFLATED) as z:
    for root,_,files in os.walk(name):
        for f in sorted(files):
            p=os.path.join(root,f); z.write(p,p)
" "$NAME")
(cd "$DIST" && sha256sum "$NAME.zip" > "$NAME.zip.sha256")
ls -la "$DIST/$NAME.zip"; cat "$DIST/$NAME.zip.sha256"
