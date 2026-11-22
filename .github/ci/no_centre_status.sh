#!/bin/bash
# v63 (Marko, 22.11.2026): "recording blob can go away. Something which is happening in the middle of the screen needs to go away."
# Fails the build if a centre-of-screen status window (TakeHUD) comes back, or if the bottom ellipse disappears.
cd "$(dirname "$0")/../../mac/Sources" || exit 2
bad=0
if ls | grep -qi 'TakeHUD'; then echo "FAIL: a TakeHUD file is back"; bad=1; fi
if grep -nI 'TakeHUD' *.swift; then echo "FAIL: TakeHUD is referenced"; bad=1; fi
if grep -nE '(screen|sc|scr|\$0)\.(visibleFrame|frame)\.midY' *.swift; then
  echo "FAIL: a window is placed at the middle of a screen (a screen frame.midY)"; bad=1; fi
[ -f RecordingIndicator.swift ] || { echo "FAIL: RecordingIndicator.swift is missing"; bad=1; }
grep -q 'RecordingIndicator.shared.start' main.swift || { echo "FAIL: RecordingIndicator is not started in main.swift"; bad=1; }
grep -q 'vf.minY + 14' RecordingIndicator.swift || { echo "FAIL: the indicator is no longer at the bottom"; bad=1; }
[ $bad = 0 ] && echo "ok: no centre status window; bottom ellipse present"
exit $bad
