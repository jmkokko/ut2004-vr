#!/usr/bin/env bash
# Build the x64 d3d9.dll proxy with MSVC (via a Windows-side copy, since cl.exe dislikes \\wsl$ paths)
# and install it plus openvr_api.dll and the SteamVR action manifest into the lab install.
set -euo pipefail
LAB=${LAB:-/mnt/c/UT2004-VRLab}
HERE="$(cd "$(dirname "$0")" && pwd)"
W=/mnt/c/ut2004vr-build
mkdir -p "$W"
rm -rf "$W/proxy" && cp -r "$HERE/proxy" "$W/proxy"
[ -d "$W/third_party/openvr" ] || { mkdir -p "$W/third_party"; cp -r "$HERE/third_party/openvr" "$W/third_party/"; }
/mnt/c/Windows/System32/cmd.exe /c 'C:\ut2004vr-build\proxy\build.bat' 2>&1 | tr -d '\r' | grep -v -E '^\s*$|Creating library|d3d9proxy.cpp$'
cp "$W/build/d3d9.dll" "$LAB/System/d3d9.dll"
cp "$HERE/third_party/openvr/bin/win64/openvr_api.dll" "$LAB/System/"
mkdir -p "$LAB/System/UT2004VR"
cp "$HERE"/proxy/actions/*.json "$LAB/System/UT2004VR/"
[ -f "$LAB/System/UT2004VR_proxy.ini" ] || cp "$HERE/proxy/UT2004VR_proxy.ini" "$LAB/System/"
cp "$HERE/Play-VR.bat" "$LAB/System/"
ls -la "$LAB/System/d3d9.dll"
