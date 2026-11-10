# Takeover

**v13, 10.11.2026: TTT's transcription features, same copy (Marko: "upgrade my local app ... to have the same features as my TTT app for voice transcription with all these models and everything. Same copy.").** Skill: `skills/voice-to-text` (linked as ~/.claude/skills/voice-to-text). Ported from TTT_MINI builds 577-596 and the CLI scribe; TTT itself untouched.
- **The 13 engines** (`Catalog.swift`, TTT's order and quotas): Parakeet (MANTRA_VOICE ears, Marko's Mac only), Whisper Turbo on this Mac (takes the place of TTT's Android on-device), Groq turbo, Groq large-v3, Cloudflare Workers AI, Gemini Flash-Lite, Deepgram Nova-3, AssemblyAI, Speechmatics, Google Speech v1, Google Chirp 3, Soniox, ElevenLabs (the last two paid: only when picked). One adapter each in `Adapters.swift`.
- **Engine panel** (⚙ Settings, section 2): all 13 as round buttons with the accuracy of the chosen language in brackets (TTT's benchmark of 9.11.2026, shipped; Scores.record replaces one when measured), "free · 480 min/day" / "free credit · 38,333 min, once" / "paid · $0.10/h", and the key in use ("Groq 2/3 in use"). One engine per language (EN, HR, AUTO), like TTT's H and E keys. The old choice (AssemblyAI AUTO) migrated once (flag v13engines).
- **Keys** (`KeyImport.swift`): no key field. `Import keys from file...` and `Re-test keys`; KeyScan sorts every token by shape (gsk_ Groq, AIza Google to Gemini and Speech v1, sk-ant- Anthropic, 32 hex AssemblyAI, 40 hex Deepgram, 64 hex Soniox, 32 mixed Speechmatics, sk_ ElevenLabs, account id + token Cloudflare, service-account JSON Chirp); each new key is tested with a free call (a list/auth call); only the working go in, numbered in file order; refused ones are remembered (rejected.json, fingerprints) and not asked again until Re-test. On this Mac the files in ~/Downloads/API whose names say a speech or Claude provider come in by themselves at launch and when ⚙ opens (other files there are never opened). Measured 10.11.2026: Groq 3 of 8 working (as on TTT), AssemblyAI 20, Gemini 25, Deepgram, Speechmatics, Soniox, Cloudflare, service account 1 each, Anthropic 2.
- **Rotation, always on** (`Ring` in Keys.swift): the key in use stays until it fails, then the next number, after the last it wraps to key 1; rests as TTT: rate limit a minute (or Retry-After), refused an hour, out of free use until 00:00 UTC. The status line says "Groq 1/3 out of free use → Groq 2/3". No switch. Test: `defaults write com.mantra.voicetotext testDropKeys -int 1`, then `--hear groq_v3 file.wav en --only` prints "ring: Groq 1/3 no connection → Groq 2/3"; delete the default.
- **Chain** (`Chain.swift`): the engine picked first; when its keys all fail the walk goes through TTT's order for the language (free, with a key, with free minutes left in its window counted in Quota); Whisper on this Mac among the last. Said on the status line and in History ("ElevenLabs failed → Parakeet").
- **Croatian**: auto correct is off for Croatian takes (Prefs.correctCroatian, tick in ⚙; TTT's maAiCorrectDictation). The STYLE button is not touched. AUTO: Croatian recognised by the engine's language, or by č ć š ž đ in the text.
- **History**: Re-transcribe with... lists the 13 engines with the accuracy for the language chosen beside it (greyed without a key) and a language picker; the new version records the engine that really answered.
- **CLI**: `--hear <engine id> <file> [en|hr|auto] [--only]`, `--keys` (numbers), `--parse <file>`, `--import-keys <files>`, `--retest-keys`.
- **Measured** (spoken test files, free engines, 10.11.2026): Groq large-v3 and turbo, Deepgram, Cloudflare, Gemini, AssemblyAI, Speechmatics, Google v1, Chirp 3 each wrote the English or Croatian sentence word for word (Speechmatics and Google v1 with small slips); Parakeet via the fallback; rotation shown with testDropKeys; ElevenLabs without key fell back to Parakeet. Deepgram AUTO needs language=multi (detect_language misheard), Speechmatics AUTO is plain "auto".
- **Not proven:** a real microphone take by Marko, the engine panel clicked by hand, the History picker clicked, Soniox and ElevenLabs transcription (paid, no call made), a daily-quota rest at 00:00 UTC, the by-itself import at the next launch, Whisper-on-this-Mac fallback in the chain, accuracy measured on this Mac (the percentages are TTT's).


**v11, 8.11.2026:** (1) STYLE no longer echoes the text twice: some boxes take AXSelectedText but ignore the selected range and insert at the caret, so old and new text both stayed. `Restyle.write` (Hands.swift) now compares the box with exactly what it should hold, then sets the whole value, then selects all and types over. (2) ⚙ Settings by importance: 1 the key that starts listening, 2 the models (Whisper, the STYLE Claude), 3 the API keys, then the rest. Compiled by GitHub Actions only; not yet tested by Marko.

**State 8.11.2026, v10:** styling no longer leaves an empty line between paragraphs (Marko: "Write everything without spaces between paragraphs"): the rule in `Rules.base` (Engines.swift) says one paragraph per line with no empty line, and `Style.noEmptyLines` collapses every run of line breaks to one after the model answers, so it holds even when the model ignores the rule. Applies to all styling paths (Style.run).

Started 1.11.2026.

## v3: one app, and the duck (1.11.2026)

- Mac: `mac/Sources/Local.swift` holds Ears (builtIn / server), VoiceServer, Warm, Merge (from com.mantra.markotranscribe
  and ~/Library/Application Support/Marko Transcribe, once, flag `mergedFromRT`), Duck (CoreAudio
  VirtualMainVolume on the default output; the level saved in UserDefaults `duckSaved`/`duckDevice` until it is put back).
  TakeMark writes take-open in both the new and the old folder (voiced.py of MANTRA_VOICE reads the new one from its next
  start). The old notification names com.mantra.markotranscribe.* are heard too.
- Windows: `windows/src/Duck.cs` (IAudioEndpointVolume by COM, calls on a pool thread with a 2 s limit, saved level in
  duck.txt), Prefs.Duck, ⚙ checkbox, `--duck-test`. Version 3 in the csproj.
- Proven: Mac `--duck-test` 49 % → 6 % → 49 % on the ADAM D3V; Windows VM 50 % → 6 % → 50 %; an artificial take through
  the :8837 ears ("This is a test of the United Voice to Text application from Marko."); his settings, keys and history
  moved; ⚙ off screen, nothing cut. The old /Applications/Transcribe Voice to Text RT (Mantra).app is in the Trash.
- **Published 1.11.2026** at Marko's yes (he heard the drop: "it works"): release v3, page shows 3, all three buttons 200.
  A real take by hand with the speakers playing.

## Mac (1.11.2026)

Built from MARKO_TRANSCRIBE v29's sources (copied, then changed; the two now live apart). Bundle id
com.mantra.voicetotext, data in ~/Library/Application Support/Mantra Voice to Text, log ~/Library/Logs/mantra-voice-to-text.log.
Removed: the :8837 voice server and its starter, the ears' warm socket, ffmpeg, Speechify's sounds (Tink/Pop now),
the key-file picker's ~/Downloads/API start, every "Marko" in prompts and corrections. Auto correct defaults to None
until a key is added (then Haiku), so STYLE is grey for a new user.

**Proven 1.11.2026** (artificial speech, `say` Samantha and Lana, test mode, nothing typed): English word for word,
Croatian with one join ("uzoru"), AUTO picked the language each time; GPU about 3 s after the load, processor fallback
about 26 s. Settings and the pill checked as off-screen pictures. **Not proven:** the Claude call in this build (same
code as v29, which Marko uses daily), a real microphone take, the download button end to end (the model was linked in
by hand), a Mac other than this M1 Pro, an Intel Mac (not supported: arm64 only).

## Windows (1.11.2026)

`windows/` (README.md there): C# .NET 8, WPF, Whisper.net 1.9.1 (whisper.cpp, CPU), NAudio, the official Anthropic C#
SDK. Built inside the Parallels VM "Windows 11" (ARM64, 4 cores, 6 GB): .NET SDK 8.0.427 in `C:\dotnet`,
`windows\build.ps1 [-Publish]` copies the sources to `C:\mvt`, builds there and puts the zips into `windows/dist/`
(gitignored): **MantraVoiceToText-v1-win-x64.zip** and **MantraVoiceToText-v1-win-arm64.zip**, one self-contained
`MantraVoiceToText.exe` in each. Data: `%LOCALAPPDATA%\Mantra Voice to Text` (settings.json, key.bin with DPAPI,
history.json, log.txt, models\). The SDK zip, vc_redist and the NuGet cache stay in `windows/build/` so nothing is
downloaded twice. The VM got the Microsoft VC++ runtime (arm64) installed for the tests.

Same as the Mac: the pill (✕ [AUTO] meter ⏸ COPY STYLE ⚙ send, line above or below), F1 / F1 / Esc, silence gate
(-45 dBFS, 0.5 s), Auto correct with the Mac's rules (Marko's name taken out), STYLE on the focused box, the ⚙ menu,
Settings with ON · OFF · name · TOP · ✕. Different: typing is clipboard + Ctrl+V (only the clipboard's text is given
back); Auto correct defaults to Claude Haiku as asked (the Mac build defaults to None until a key is added); a tray icon;
Whisper AUTO is not held to Croatian/English (whisper.cpp's own detection); the model download always resumes (.part +
Range, retries, goes on by itself at the next start; Marko 1.11.2026).

**Proven 1.11.2026 in the VM** (log lines and pictures in `windows/docs/`):
- `--take test/en-test.wav`: "Hello, this is a test of the dictation app on Windows. Please send me the report by
  Friday, and um, thank you for your help." word for word, about 35 s (dev build) to 45 to 55 s (release exe) for 7.5 s of
  audio on 4 virtual ARM cores, CPU only; the same warm (three takes in one run: 35.2, 34.3, 33.6 s).
- `test/hr-test.wav` (Lana): "Dobar dan, ovo je proba diktiranja na Windowsu. Molim te pošalji mi izvještaj do petka."
  word for word, language found as hr, 44.9 s.
- Typed into Windows 11 Notepad (read back by UI Automation, exact); with no key the line says "typed 25 words · Auto
  correct needs an Anthropic key in ⚙" and the raw words are typed.
- Desktop focused: "25 words did not land · press COPY", COPY white, the blob stays; COPY then put the 124 characters
  on the clipboard (read back by the app) and turned green.
- STYLE (with `--test-style-fake`, capitals instead of Claude): the whole Notepad box rewritten, and a selection of the
  last 5 words rewritten alone; Notepad kept the focus throughout.
- F1 (a real key event inside Windows) started a take on the VM's microphone, Esc threw it away (nothing written down);
  the ⚙ menu opened; Notepad stayed the foreground window the whole time (the blob never took the focus).
- Silence: test/silence.wav → "nothing said (2.0 s, -140 dB): not sent".
- The download resumes: started, killed at 4,717,622 bytes, started again without any switch → "starting at 4717622
  bytes (Range: bytes=4717622-)", killed at 6,918,154, a third start went on from there; the 18 MB downloaded were
  byte-identical to the model's first 18 MB; then the real model was put back (only ~18 MB used of the SIM).
- The arm64 release zip, unzipped to a fresh folder with no .NET on the path, transcribed the test file.
- The x64 release zip runs under Windows-on-ARM emulation: it starts, and Whisper (the NoAvx runtime, since emulation
  has no AVX) loads the model in 17 to 41 s; the transcription itself did not finish in 10 minutes there (emulated, no
  SIMD), so **x64 transcription is not proven**: it needs a real Intel / AMD PC.
- `--pill-shot` faces (ready, recording, writing, not landed with COPY white, styling with STYLE green, no auto correct
  with STYLE grey, copied, no key, line below) and `--settings-shot`.

**Not proven:** the real Claude call (Auto correct, STYLE, the key's Test button) on Windows (no key of Marko's was
used: the code path without a key was); a mouse click on the blob (buttons were pressed with `--press`, which calls the
same action; dragging was not tried); a real voice through a real microphone (the F1 take was thrown away); a real x64
PC (see the x64 line above); a PC without the VC++ runtime after the "Get it" message (the message is code, the failure
before it was seen); the download from 0 to the end (only ~18 MB); the hotkey change in Settings; the history window's
buttons; Windows 10; high-DPI multi-monitor placement; antivirus / SmartScreen reaction to an unsigned exe (it is not
signed: Windows will warn "unknown publisher" on first start).

### Windows v2 (1.11.2026): Voice to Text (Mantra)

Renamed at Marko's word: the name everywhere the user sees it (window titles, Settings' first row "Voice to Text
(Mantra)   v2", tray tooltip, menus, the exe's version info: ProductName / FileDescription "Voice to Text (Mantra)",
ProductVersion 2, FileVersion 2.0.0.0). Exe `VoiceToTextMantra.exe`, zips `windows/dist/VoiceToTextMantra-v2-win-x64.zip`
and `-win-arm64.zip` (the v1 zips are still beside them). Data folder `%LOCALAPPDATA%\Voice to Text (Mantra)`: v1's
`%LOCALAPPDATA%\Mantra Voice to Text` is moved there at the first start (kept as it is when the move fails). The C#
namespace and the .csproj file name stay MantraVoiceToText (not seen by anyone).

**Proven 1.11.2026 (arm64 release zip in the VM):** the first start logged "data folder: moved …\Mantra Voice to Text
to …\Voice to Text (Mantra)", the model came along (574,041,195 bytes, no download line in the log), and the English
test file was written down word for word (34.2 s, then 35.0 s). `--pill-shot` and `--settings-shot` from the released exe
looked at: the new name and v2 in Settings; the exe's version info read back. **Not proven for v2:** the x64 zip was
built but not run (v1's x64 ran only under emulation), and everything listed as not proven for v1.

## v2 (1.11.2026): renamed Voice to Text (Mantra)

Mac: `Voice to Text (Mantra).app`, data ~/Library/Application Support/Voice to Text (Mantra) (v1's folder moves once),
log ~/Library/Logs/voice-to-text-mantra.log, bundle id unchanged (com.mantra.voicetotext). Release v2 holds
VoiceToTextMantra-v2-mac.zip, -win-x64.zip, -win-arm64.zip; the site serves the Mac zip itself and links the Windows ones.
Proven: Mac Croatian take after the folder move (model not downloaded again); Windows arm64 English take after its move.

## Downloads always the newest (1.11.2026)

MANTRA_MANIFEST modules/download-always-latest.md. The buttons' addresses carry no version and are never edited again:
- Mac: `https://mantravoicetotext.pages.dev/download/VoiceToText-mac.zip` (hosted on the page, about 2 MB)
- Windows: `https://github.com/markoboskoauroville/mantra-voice-to-text-downloads/releases/latest/download/VoiceToText-win-x64.zip`
  and `.../VoiceToText-win-arm64.zip` (public downloads repo; over Pages' 25 MB limit)

**The release step is `tools/publish.sh`, called at the end of `mac/build.sh`** (`--no-publish` skips it): the version N
from `appVersion` in mac/Sources/Engines.swift, checked against the csproj's InformationalVersion; the Windows zips of vN
built in the VM by itself (`windows/tools/vmx.sh … build.ps1 -Publish`) when windows/dist lacks them; release vN on
the downloads repo created if missing and marked Latest, with the fixed names (VoiceToText-win-x64.zip, -win-arm64.zip,
VoiceToText-mac.zip) and the versioned names beside them, an asset with the same sha256 never uploaded twice;
then `site/deploy.sh` (Mac zip to site/public/download/VoiceToText-mac.zip, `<span data-app-version>`, `data-mac-mb`,
`data-win-mb` written from the build, link guard, SEO with downloadUrl = the fixed Mac address, wrangler); then the live
check (each button 200 with the right size, the Mac file sha256-compared, the page showing vN). A new version therefore
is: raise appVersion and the csproj Version, `mac/build.sh`. Old addresses: `site/public/_redirects` sends
VoiceToTextMantra-v*-mac.zip and MantraVoiceToText-v*-mac.zip 301 to the fixed one; on the release the versioned assets
of v1 and v2 stay, so links already sent keep working.

**Done for v2 without a rebuild** (the local zips had the release's sha256): the fixed-name copies uploaded to release v2
(still Latest), the page deployed. Live 1.11.2026: Mac 200, 2,241,118 bytes; Windows x64 200, 74,196,736; arm64 200,
70,009,531; the page shows Version 2; /VoiceToTextMantra-v2-mac.zip, -v1 and MantraVoiceToText-v1-mac.zip answer 301 →
/download/VoiceToText-mac.zip → 200. **Not run yet:** a real new version through `mac/build.sh` (the release-create and the
VM build branches of publish.sh have not been exercised).

## v7 (1.11.2026, evening): the voice through launchd

- `VoiceServer.ensure()` (mac/Sources/Local.swift): when ~/Library/LaunchAgents/com.mantra.voiced.plist exists it runs
  `launchctl kickstart gui/<uid>/com.mantra.voiced` (bootstrap if not loaded), never nohup beside it; elsewhere nohup as
  before. Cause: two voiced.py fought over :8837 (MANTRA_VOICE TAKEOVER, v21–v22).
- Built `./build.sh --no-publish`, installed, opened with --login. **Not published**: the release and page still show 6.
- Tests: `defaults write com.mantra.voicetotext ears builtIn; … testNoTyping -bool true; … hear whisperHR|whisperAuto|whisperEN`,
  then `"<app>/Contents/MacOS/Voice to Text (Mantra)" --take windows/test/<file>.wav`, the result in
  ~/Library/Logs/voice-to-text-mantra.log ("test, not typed: …"). Put back hear/ears, delete testNoTyping, move the test
  entries out of history/.
