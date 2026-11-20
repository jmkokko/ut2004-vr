#!/usr/bin/env bash
# Copy the UT2004VR UnrealScript package into the lab install and compile it with UCC.
set -euo pipefail
LAB=${LAB:-/mnt/c/UT2004-VRLab}
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$LAB/UT2004VR"
cp -r "$HERE/UT2004VR" "$LAB/UT2004VR"
grep -q '^EditPackages=UT2004VR' "$LAB/System/UT2004.ini" || \
  sed -i 's/^\(EditPackages=AssaultBP\)\r\?$/\1\r\nEditPackages=UT2004VR\r/' "$LAB/System/UT2004.ini"
# the VR settings file Play-VR.bat starts the game with (made by Play-VR.bat itself when missing): VRConsole and the
# intro with the VR mutator. UT2004.ini stays stock apart from EditPackages, so a normal launch is plain UT2004.
rm -f "$LAB/System/UT2004VR.u"
cd "$LAB/System"
./UCC.exe make -silent 2>&1 | tr -d '\r' | grep -v '^$' | tail -40
ls -la "$LAB/System/UT2004VR.u"
