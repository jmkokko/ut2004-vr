#!/usr/bin/env bash
# Copy the UT2004VR UnrealScript package into the lab install and compile it with UCC.
set -euo pipefail
LAB=${LAB:-/mnt/c/UT2004-VRLab}
HERE="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$LAB/UT2004VR"
cp -r "$HERE/UT2004VR" "$LAB/UT2004VR"
grep -q '^EditPackages=UT2004VR' "$LAB/System/UT2004.ini" || \
  sed -i 's/^\(EditPackages=AssaultBP\)\r\?$/\1\r\nEditPackages=UT2004VR\r/' "$LAB/System/UT2004.ini"
# UT's console -> VRConsole: adds the VR mutator to every game the menus start, and runs the headset menu in the
# main menus (only the [Engine.Engine] line; the other Console= line is [Engine.Console]'s hot key section)
sed -i 's/^Console=XInterface.ExtendedConsole\r\?$/Console=UT2004VR.VRConsole\r/' "$LAB/System/UT2004.ini"
# the startup intro (a Matinee cinematic) runs with the VR mutator too, so it plays in the headset in 3D
sed -i 's/^LocalMap=NvidiaLogo.ut2\r\?$/LocalMap=NvidiaLogo.ut2?Mutator=UT2004VR.VRMutator\r/' "$LAB/System/UT2004.ini"
rm -f "$LAB/System/UT2004VR.u"
cd "$LAB/System"
./UCC.exe make -silent 2>&1 | tr -d '\r' | grep -v '^$' | tail -40
ls -la "$LAB/System/UT2004VR.u"
