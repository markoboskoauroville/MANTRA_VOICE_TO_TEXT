#!/bin/bash
# v63 (Marko, 22.11.2026): "recording blob can go away. Something which is happening in the middle of the screen needs to go away."
# Fails the build if a centre-of-screen status window (TakeHUD) comes back, if the bottom ellipse disappears, or (v64) if ANY new
# window or panel is created in a Swift file or place not listed below.
# Optional argument: the Sources folder to check (default mac/Sources of this repo); used to test the check on a throwaway copy.
SRC="${1:-$(dirname "$0")/../../mac/Sources}"
cd "$SRC" || exit 2
bad=0
if ls | grep -qi 'TakeHUD'; then echo "FAIL: a TakeHUD file is back"; bad=1; fi
if grep -nI 'TakeHUD' *.swift; then echo "FAIL: TakeHUD is referenced"; bad=1; fi
if grep -nE '(screen|sc|scr|\$0)\.(visibleFrame|frame)\.midY' *.swift; then
  echo "FAIL: a window is placed at the middle of a screen (a screen frame.midY)"; bad=1; fi
[ -f RecordingIndicator.swift ] || { echo "FAIL: RecordingIndicator.swift is missing"; bad=1; }
grep -q 'RecordingIndicator.shared.start' main.swift || { echo "FAIL: RecordingIndicator is not started in main.swift"; bad=1; }
grep -q 'vf.minY + 14' RecordingIndicator.swift || { echo "FAIL: the indicator is no longer at the bottom"; bad=1; }

# The allowed list: Swift file = number of places that create or subclass a window/panel (NSWindow, NSPanel, BlobPanel, DisplayPanel).
# Counted 22.11.2026 (v64). Add a line only if the new window is NOT a status window in the middle of the screen.
ALLOWED="HoverCard.swift=1 Magnet.swift=3 RecordingIndicator.swift=1 Settings.swift=1 Suggest.swift=1 Toast.swift=1 main.swift=3"
for f in *.swift; do
  n=$(grep -cE '\b(NSWindow|NSPanel|BlobPanel|DisplayPanel)\(|class [A-Za-z_]+ *: *(NSWindow|NSPanel|BlobPanel|DisplayPanel)\b' "$f")
  [ "$n" = 0 ] && continue
  allowed=$(echo " $ALLOWED " | grep -o " $f=[0-9]*" | cut -d= -f2)
  if [ -z "$allowed" ] || [ "$n" -gt "$allowed" ]; then
    echo "FAIL: $f creates $n window(s), allowed ${allowed:-0}: new window: add it to the list only if it is not a status window in the middle of the screen"; bad=1
  fi
done
[ $bad = 0 ] && echo "ok: no centre status window; bottom ellipse present; every window creation is on the list"
exit $bad
