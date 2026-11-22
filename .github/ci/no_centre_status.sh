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
# v65 (Marko, 22.11.2026: "Blob comes to that screen" where the cursor is): the indicator's screen comes from the focus resolver,
# the mouse is only the last fallback, and the AX (top-left) to AppKit (bottom-left) conversion keeps its formula.
grep -q 'FocusScreen.resolve()' RecordingIndicator.swift || { echo "FAIL: the indicator's screen does not come from FocusScreen.resolve()"; bad=1; }
if grep -n 'mouseLocation' RecordingIndicator.swift; then echo "FAIL: RecordingIndicator uses the mouse; only FocusScreen may, as its last fallback"; bad=1; fi
[ "$(grep -c 'mouseLocation' FocusScreen.swift)" = 1 ] || { echo "FAIL: the mouse must be used exactly once in FocusScreen (rule d, last)"; bad=1; }
a=$(grep -n 'b: focused element' FocusScreen.swift | head -1 | cut -d: -f1); m=$(grep -n 'mouseLocation' FocusScreen.swift | head -1 | cut -d: -f1)
[ -n "$a" ] && [ -n "$m" ] && [ "$m" -gt "$a" ] || { echo "FAIL: in FocusScreen the mouse is not after the focus rules"; bad=1; }
grep -q 'primaryHeight - r.minY - r.height' FocusScreen.swift || { echo "FAIL: the AX to AppKit conversion formula changed"; bad=1; }
python3 - <<'PY' || bad=1
# unit-style check of the same conversion on both real layouts (BenQ portrait 1440x2560 primary, MacBook 1512x982 at 1440,351)
frames=[(0,0,1440,2560),(1440,351,1512,982)]; ph=frames[0][3]
def conv(x,y,w,h): return (x, ph-y-h, w, h)
def idx(r):
    cx,cy=r[0]+r[2]/2,r[1]+r[3]/2
    for i,f in enumerate(frames):
        if f[0]<=cx<f[0]+f[2] and f[1]<=cy<f[1]+f[3]: return i
cases=[((300,400,2,18),0),((300,2500,2,18),0),((1500,1300,2,18),1),((2400,2000,2,18),1),((1500,300,2,18),None),((100,100,800,600),0),((1500,1250,600,50),1)]
# AX top-left y: BenQ spans 0..2560; MacBook spans y 1227..2209 (2560-1333 .. 2560-351)
for r,want in cases:
    got=idx(conv(*r))
    if got!=want: print("FAIL: conversion",r,"gave screen",got,"wanted",want); raise SystemExit(1)
print("ok: AX to AppKit conversion places the 6 sample rectangles on the right screen of both layouts")
PY

# v66 (Marko, 22.11.2026: STYLE "nothing is happening"): STYLE cannot fail silently or stop on a switch, and never sends a message.
grep -q 'appendLog("STYLE \\(ok ? "done" : "NOT done")' main.swift || { echo "FAIL: styleDone no longer logs every outcome (STYLE must never be silent)"; bad=1; }
if grep -nE 'STYLING is switched off|nothing is changed; pick COR' main.swift; then echo "FAIL: STYLE refuses a press on a switch again (the v66 cause)"; bad=1; fi
grep -q 'StyleChain.run(input, steps: StyleChain.steps' main.swift || { echo "FAIL: STYLE does not walk StyleChain (Opus, then Groq)"; bad=1; }
grep -q 'Claude.style' StyleChain.swift && grep -q 'GroqStyle.style' StyleChain.swift || { echo "FAIL: StyleChain lost Claude or Groq"; bad=1; }
if grep -nE 'kVK_Return|kVK_ANSI_KeypadEnter|keyCode: *36|CGKeyCode\(36\)|0x24' Hands.swift Target.swift main.swift StyleChain.swift; then echo "FAIL: a Return key in the STYLE code (it would send a message)"; bad=1; fi
if grep -nE 'styleButtonOn|toggleStyling|qStyle\\b' main.swift Settings.swift MenuBar.swift; then echo "FAIL: the STYLING switch is back (the STYLE button always styles)"; bad=1; fi
grep -q 'keepOrder: true' StyleChain.swift || { echo "FAIL: STYLE no longer tells the models to keep the order"; bad=1; }
grep -q -- '--selftest' main.swift || { echo "FAIL: the STYLE self test is gone"; bad=1; }

[ $bad = 0 ] && echo "ok: no centre status window; bottom ellipse present; every window creation is on the list"
exit $bad
