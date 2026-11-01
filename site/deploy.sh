#!/bin/bash
# deploy.sh: mantravoicetotext.pages.dev (site/public) on Cloudflare Pages. The account id and token are read from
# Marko's API folder, never printed. The Mac zip is copied from mac/dist; the Windows zip is linked on the GitHub release
# of markoboskoauroville/mantra-voice-to-text-downloads when it is over Pages' 25 MB limit.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(grep -E '^let appVersion' mac/Sources/Engines.swift | grep -oE '[0-9]+')
[ -f "mac/dist/VoiceToTextMantra-v$V-mac.zip" ] || { echo "no mac/dist/VoiceToTextMantra-v$V-mac.zip: run mac/build.sh"; exit 1; }
rm -f site/public/VoiceToTextMantra-*-mac.zip site/public/MantraVoiceToText-*-mac.zip; cp "mac/dist/VoiceToTextMantra-v$V-mac.zip" site/public/
grep -q "VoiceToTextMantra-v$V-mac.zip" site/public/index.html || { echo "index.html does not link VoiceToTextMantra-v$V-mac.zip"; exit 1; }
# every page with the donation bowl is search-engine optimised (Marko, 31.10.2026)
python3 ~/Developer/MANTRA_MANIFEST/kits/seo/seo_app_page.py site/public --url https://mantravoicetotext.pages.dev --name "Voice to Text (Mantra)" --version "$V" --download "VoiceToTextMantra-v$V-mac.zip" --keywords "voice to text, dictation app, speech to text mac, speech to text windows, whisper offline, voice typing, dictate prompts, free dictation" --image img/life-prompt.jpg --os "macOS, Windows"
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
