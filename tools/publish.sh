#!/bin/bash
# publish.sh: the release step (MANTRA_MANIFEST modules/download-always-latest.md). One run, no hand step:
#   1. the version N from mac/Sources/Engines.swift (appVersion), checked against windows/src/*.csproj
#   2. the Windows zips of vN: built in the Parallels VM (windows/build.ps1 -Publish) if windows/dist lacks them
#   3. release vN on the PUBLIC repo markoboskoauroville/mantra-voice-to-text-downloads, marked latest, with the
#      fixed-name assets VoiceToText-win-x64.zip, VoiceToText-win-arm64.zip, VoiceToText-mac.zip (the page's buttons link
#      releases/latest/download/<fixed name>) and the versioned copies beside them; an asset already there with the
#      same sha256 is not uploaded again (SIM data)
#   4. site/deploy.sh: the Mac zip at download/VoiceToText-mac.zip, the version and sizes written into the page
#   5. checks the live page: every button answers 200 with the right size, the page shows vN
# Called at the end of mac/build.sh (unless --no-publish). Alone: tools/publish.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=markoboskoauroville/mantra-voice-to-text-downloads
SITE=https://mantravoicetotext.pages.dev
V=$(grep -E '^let appVersion' mac/Sources/Engines.swift | grep -oE '[0-9]+')
WV=$(grep -oE '<InformationalVersion>[0-9]+' windows/src/*.csproj | grep -oE '[0-9]+$')
[ "$V" = "$WV" ] || { echo "version differs: Mac $V, Windows $WV (windows/src/*.csproj): make them the same first"; exit 1; }
MAC="mac/dist/VoiceToTextMantra-v$V-mac.zip"
[ -f "$MAC" ] || { echo "no $MAC: run mac/build.sh"; exit 1; }
if [ ! -f "windows/dist/VoiceToTextMantra-v$V-win-x64.zip" ] || [ ! -f "windows/dist/VoiceToTextMantra-v$V-win-arm64.zip" ]; then
  echo "building Windows v$V in the VM"
  windows/tools/vmx.sh 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build.ps1' -Publish
fi
for r in x64 arm64; do [ -f "windows/dist/VoiceToTextMantra-v$V-win-$r.zip" ] || { echo "no windows/dist/VoiceToTextMantra-v$V-win-$r.zip"; exit 1; }; done

# the files under their release names (fixed and versioned), in a temporary folder
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for r in x64 arm64; do
  cp "windows/dist/VoiceToTextMantra-v$V-win-$r.zip" "$T/VoiceToText-win-$r.zip"
  cp "windows/dist/VoiceToTextMantra-v$V-win-$r.zip" "$T/"
done
cp "$MAC" "$T/VoiceToText-mac.zip"; cp "$MAC" "$T/"

if ! gh release view "v$V" -R $REPO >/dev/null 2>&1; then
  gh release create "v$V" -R $REPO --latest --title "Voice to Text (Mantra) $V" \
    --notes "Voice to Text (Mantra) $V. Mac: Apple Silicon, macOS 14+. Windows: 10/11, x64 or ARM. Install steps: $SITE"
fi
have=$(gh release view "v$V" -R $REPO --json assets -q '.assets[]|"\(.name) \(.digest)"')
for f in "$T"/*.zip; do
  n=$(basename "$f"); d="sha256:$(shasum -a 256 "$f" | cut -d' ' -f1)"
  if grep -qxF "$n $d" <<<"$have"; then echo "release v$V: $n already there"; else
    echo "release v$V: uploading $n"; gh release upload "v$V" -R $REPO "$f" --clobber; fi
done
gh release edit "v$V" -R $REPO --latest >/dev/null

site/deploy.sh

# the live check
fail=0
check() { # url local-file: 200 and the same size (big files by HEAD; small ones fetched whole, sha256 compared)
  local want code len h
  want=$(stat -f %z "$2")
  if [ "$want" -lt 26000000 ]; then
    read -r code len < <(curl -sL --max-time 120 -o "$T/check" -w '%{http_code} %{size_download}\n' "$1" || true)
    if [ "$code" = 200 ] && [ "$(shasum -a 256 < "$T/check")" != "$(shasum -a 256 < "$2")" ]; then len="$len (other bytes)"; fi
  else
    h=$(curl -sIL --max-time 60 "$1" | tr -d '\r' || true)
    code=$(grep -iE '^HTTP/' <<<"$h" | tail -1 | awk '{print $2}' || true)
    len=$(grep -i '^content-length:' <<<"$h" | tail -1 | awk '{print $2}' || true)
  fi
  if [ "$code" = 200 ] && [ "$len" = "$want" ]; then echo "live ok: $1 -> 200, $len bytes"; else echo "LIVE WRONG: $1 -> $code, $len bytes (want $want)"; fail=1; fi
}
sleep 5
G=https://github.com/$REPO/releases/latest/download
check "$SITE/download/VoiceToText-mac.zip" "$MAC"
check "$G/VoiceToText-win-x64.zip" "windows/dist/VoiceToTextMantra-v$V-win-x64.zip"
check "$G/VoiceToText-win-arm64.zip" "windows/dist/VoiceToTextMantra-v$V-win-arm64.zip"
if curl -s --max-time 30 "$SITE/" | grep -q "<span data-app-version>$V</span>"; then echo "live ok: the page shows version $V"; else echo "LIVE WRONG: the page does not show version $V"; fail=1; fi
[ $fail = 0 ] && echo "published v$V: $SITE" || { echo "published v$V, but the live check failed (above)"; exit 1; }
