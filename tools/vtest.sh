#!/bin/bash
# Lab test run (developer tool): starts the lab install with the proxy's mock headset, runs a console command chain,
# and prints the log lines that match. Every ini the run can change is backed up first and put back afterwards.
#
# usage: [MD=<MockDemo>] [LOOPS=n] [DSTART=frame DSTEP=frames] [PLAIN=1] tools/vtest.sh "<TestExec a|b|c>" "<url>" "<grep>"
#   MD      the proxy's mock demo (default f: hand held out, the trigger pressed once to join, nothing else)
#   LOOPS   ~2 s polls before the game is killed (default 60); end the chain with |exit to quit cleanly
#   DSTART  dump the eye images (12, every DSTEP frames from frame DSTART) and make eyes.png in $OUT
#   PLAIN=1 start plain UT2004 (no -ini=UT2004VR_Game.ini): the proxy must stay out of the way
# Needs universal-modder's `um` (WIN tools) and PowerShell. Never run it while you are playing: it aborts if
# UT2004 or UCC is running.
LAB=${LAB:-/mnt/c/UT2004-VRLab}
L=$LAB/System
WINEXE=$(echo "$L/UT2004.exe" | sed 's|^/mnt/\(.\)/|\U\1:\\|; s|/|\\|g')
OUT=${OUT:-${TMPDIR:-/tmp}/ut2004vr-test}
UM=${UM:-$HOME/half-life-unreal/universal-modder/bin}
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
mkdir -p "$OUT"
export PATH="$UM:$PATH"
R=$($PS -NoProfile -Command "(Get-Process UT2004,ucc -ErrorAction SilentlyContinue).Id" 2>&1 | tr -d '\r' | head -1)
if [ -n "$R" ]; then echo "UT2004 or UCC is running - abort"; exit 1; fi
INIS="UT2004VR.ini UT2004VR_proxy.ini User.ini UT2004.ini UT2004VR_Game.ini"
for f in $INIS; do [ -f "$L/$f" ] && cp "$L/$f" "$OUT/$f.bak"; done
NEWINI=""; [ -f "$L/UT2004VR.ini" ] || { printf '[UT2004VR.VRPlayerController]\r\nTestExec=\r\n' > "$L/UT2004VR.ini"; NEWINI=1; }
sed -i "s/^TestExec=.*/TestExec=$1\r/" "$L/UT2004VR.ini"
sed -i "s/^Mock=0/Mock=1/; s/^MockDemo=0/MockDemo=${MD:-f}/" "$L/UT2004VR_proxy.ini"
rm -f "$L/UT2004.log" "$L"/UT2004VR_eye*.bmp
if [ -n "$DSTART" ]; then sed -i "s/^DumpEyes=0/DumpEyes=1\r\nDumpEyesStart=$DSTART\r\nDumpEyesStep=${DSTEP:-60}/" "$L/UT2004VR_proxy.ini"; fi
VRINI="-ini=UT2004VR_Game.ini"; [ -n "$PLAIN" ] && VRINI=""
(cd "$UM/.." && timeout 20 um win launch "$WINEXE" -- $2 $VRINI -log >/dev/null 2>&1 &)
P=""
for i in $(seq ${LOOPS:-60}); do timeout 2 tail -f /dev/null; P=$($PS -NoProfile -Command "(Get-Process UT2004 -ErrorAction SilentlyContinue).Id" 2>&1 | tr -d '\r' | head -1); [ $i -gt 5 ] && [ -z "$P" ] && break; done
[ -n "$P" ] && (cd "$UM/.." && um win kill $P) && timeout 3 tail -f /dev/null
rm -f "$L/Running.ini"
for f in $INIS; do [ -f "$OUT/$f.bak" ] && { cmp -s "$L/$f" "$OUT/$f.bak" || { cp "$OUT/$f.bak" "$L/$f"; echo "restored $f"; }; }; done
[ -n "$NEWINI" ] && sed -i "s/^TestExec=.*/TestExec=\r/" "$L/UT2004VR.ini"
grep -a -E "$3" "$L/UT2004.log" | cut -c1-250
if [ -n "$DSTART" ]; then (cd "$OUT" && uv run -q --with pillow python -I -c "
from PIL import Image; import glob
fs=sorted(glob.glob('$L/UT2004VR_eye0*.bmp'))
if not fs: print('no eye dumps')
else:
  s=Image.new('RGB',(6*320,((len(fs)+5)//6)*320)); [s.paste(Image.open(f).resize((320,320)),((i%6)*320,(i//6)*320)) for i,f in enumerate(fs)]; s.save('$OUT/eyes.png'); print(len(fs),'eye dumps -> $OUT/eyes.png')"); fi
