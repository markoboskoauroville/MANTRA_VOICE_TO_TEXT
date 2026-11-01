#!/bin/bash
# deploy.sh: mantravoicetotext.pages.dev (site/public) on Cloudflare Pages. The account id and token are read from
# Marko's API folder, never printed. Normally called by tools/publish.sh (the release step); runs alone too.
# The buttons' addresses never carry a version (MANTRA_MANIFEST modules/download-always-latest.md):
#   Mac      download/VoiceToText-mac.zip        (hosted here, copied from mac/dist at every deploy)
#   Windows  github.com/markoboskoauroville/mantra-voice-to-text-downloads/releases/latest/download/VoiceToText-win-{x64,arm64}.zip
#            (over Pages' 25 MB limit; tools/publish.sh puts them on the release)
# The version and the sizes on the page are written here from the build, never by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(grep -E '^let appVersion' mac/Sources/Engines.swift | grep -oE '[0-9]+')
MAC="mac/dist/VoiceToTextMantra-v$V-mac.zip"
[ -f "$MAC" ] || { echo "no $MAC: run mac/build.sh"; exit 1; }
P=site/public
rm -f $P/VoiceToTextMantra-*-mac.zip $P/MantraVoiceToText-*-mac.zip
mkdir -p $P/download && cp "$MAC" $P/download/VoiceToText-mac.zip
mb() { python3 -c "import os,sys; print(max(1, round(os.path.getsize(sys.argv[1])/1e6)))" "$1"; }
WINMB=""; [ -f "windows/dist/VoiceToTextMantra-v$V-win-x64.zip" ] && WINMB=$(mb "windows/dist/VoiceToTextMantra-v$V-win-x64.zip")
python3 - "$P/index.html" "$V" "$(mb "$MAC")" "$WINMB" <<'PY'
import re, sys
p, v, mac, win = sys.argv[1:]
s = open(p, encoding="utf-8").read()
for attr, val in (("data-app-version", v), ("data-mac-mb", mac), ("data-win-mb", win)):
    if val:
        s, n = re.subn(rf"(<span {attr}>)[^<]*(</span>)", rf"\g<1>{val}\g<2>", s)
        assert n == 1, f"index.html: <span {attr}> not found once"
open(p, "w", encoding="utf-8").write(s)
PY
GH=https://github.com/markoboskoauroville/mantra-voice-to-text-downloads/releases/latest/download
for link in 'href="download/VoiceToText-mac.zip"' "$GH/VoiceToText-win-x64.zip" "$GH/VoiceToText-win-arm64.zip"; do
  grep -qF "$link" $P/index.html || { echo "index.html does not link $link"; exit 1; }
done
# every page with the donation bowl is search-engine optimised (Marko, 31.10.2026)
python3 ~/Developer/MANTRA_MANIFEST/kits/seo/seo_app_page.py site/public --url https://mantravoicetotext.pages.dev --name "Voice to Text (Mantra)" --version "$V" --download "download/VoiceToText-mac.zip" --keywords "voice to text, dictation app, speech to text mac, speech to text windows, whisper offline, voice typing, dictate prompts, free dictation" --image img/life-prompt.jpg --os "macOS, Windows"
if grep -qE 'VoiceToTextMantra-v[0-9]+|releases/download/v[0-9]+' $P/index.html; then echo "index.html still has a versioned download address"; exit 1; fi
eval "$(python3 - <<'PY'
import re,os
raw=open(os.path.expanduser('~/Downloads/API/Cloudflare.api.txt')).read()
acc=re.search(r'dash\.cloudflare\.com/([0-9a-f]{32})', raw).group(1)
tok=[l.strip() for l in raw.splitlines() if re.fullmatch(r'[A-Za-z0-9_\-]{30,}', l.strip())][-1]
print(f"export CLOUDFLARE_ACCOUNT_ID={acc}; export CLOUDFLARE_API_TOKEN={tok}")
PY
)"
npx --yes wrangler@3 pages project create mantravoicetotext --production-branch main >/dev/null 2>&1 || true
npx --yes wrangler@3 pages deploy site/public --project-name mantravoicetotext --branch main --commit-dirty=true 2>&1 | grep -v -i "token\|account" | tail -3
echo "deployed v$V: https://mantravoicetotext.pages.dev"
