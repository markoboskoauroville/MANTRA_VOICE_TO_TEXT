---
name: voice-to-text
description: Voice to Text (Mantra), Marko's Mac dictation app (repo MANTRA_VOICE_TO_TEXT): F1 talk, text typed at the cursor; since v13 the same 13 transcription engines as TTT, numbered key rings, key import by shape, engine panel, History re-transcribe. Use for ANY Voice to Text (Mantra) / Mac dictation app / its engines / its keys task.
---
# Voice to Text (Mantra): TTT's engines on the Mac

Marko, 10.11.2026: "upgrade my local app, my voice-to-text app, to have the same features as my TTT app for voice transcription with all these models and everything. Same copy."

## SPACE (where it happens)
- The Mac. Repo ~/Developer/MANTRA_VOICE_TO_TEXT (markoboskoauroville), Swift in mac/Sources, app /Applications/Voice to Text (Mantra).app, bundle com.mantra.voicetotext, log ~/Library/Logs/voice-to-text-mantra.log, data ~/Library/Application Support/Voice to Text (Mantra) (keys.json 0600, ring.json, history/).
- Compiled only by GitHub Actions (workflow build.yml, release vN Latest); the Mac downloads, signs "Mantra Apps", quits the old copy by AX, opens the new one. Never swiftc here.
- Key notes: ~/Downloads/API (only files named groq, deepgram, assembly, speechmatics, soniox, eleven, gemini, google-stt, cloudflare-workers, claude, anthropic, haiku are read).
- Twin: TTT_MINI (the Android keyboard, another owner) and the CLI scribe (MAC_TRANSCRIBER).

## CHARACTERS (who acts)
| Character | Who | Can | Must not |
|---|---|---|---|
| The pill | F1 stripe, EN / HR / AUTO | record, show engine, key number, status | take focus |
| The 13 engines | Catalog.swift: Parakeet, Whisper Turbo (this Mac), Groq turbo, Groq large-v3, Cloudflare, Gemini, Deepgram, AssemblyAI, Speechmatics, Google v1, Chirp 3, Soniox, ElevenLabs | write the take down | run paid ones unless picked (Soniox, ElevenLabs) |
| Groq 1/3, Groq 2/3 ... | the numbered keys of a ring (Ring in Keys.swift) | rotate always on, wrap to key 1, rest until 00:00 UTC / a minute / an hour | be shown, logged, committed |
| KeyImporter | the picker and the by-itself import | sort keys by shape, test each free, keep the working | read other secrets in ~/Downloads/API |
| Chain | retry only | wait 3 s and retry the same engine on a network error, up to 10 times | change engine by itself (never, v14) |
| History | the second tab | Re-transcribe with any engine and language, accuracy % beside each | |
| Marko | tester | the voice test, the hands | |

## PLOT
**Trigger:** change or test an engine, a key, the panel, the fallback.
1. Read TAKEOVER.md and LESSONS.md; save the request word for word in momentaryupdates.md and push first.
2. Change Sources; push main; read the run (gh run list / view --log-failed); the colour is the check.
3. Install the release: gh release download, unzip to /Applications, sign "Mantra Apps" + com.mantra.voicetotext, quit the old copy by AX (distributed notification com.mantra.voicetotext.quit, refused during a take), open the new one.
4. Tests without Marko's voice: `"<app>/Contents/MacOS/Voice to Text (Mantra)" --hear <engine id> <file> [en|hr|auto] [--only]`; `--keys`, `--parse <file>`, `--import-keys <file>`, `--retest-keys`. Spoken test files by `say` (Samantha, Lana).
   **Turning point (rotation):** `defaults write com.mantra.voicetotext testDropKeys -int 1` makes key 1 of every job fail, the answer says "Groq 1/3 no connection -> Groq 2/3"; delete the default afterwards.
   **Turning point (Croatian):** auto correct is off for Croatian takes (Prefs.correctCroatian, TTT's maAiCorrectDictation); the STYLE button is not touched.
5. A test needing his voice: one message to the master.
**Ending:** the release link and run colour, what was proven and what not.

## RULES
- Free calls only for key tests (list or auth calls); a paid transcription needs `spend ask`. Soniox and ElevenLabs only when picked.
- No key printed. Names: Groq (never Grok), Deepgram, AssemblyAI, Speechmatics, Gemini; "(Mantra)" last. Whole-number versions.
- Accuracy percentages shipped are TTT's benchmark of 9.11.2026 (circular for Groq large-v3); a measured one replaces them.

## HISTORY
- 10.11.2026, v14: no automatic engine change; retry 3 s x 10 on network errors; testNetFail default for the test.
- 10.11.2026, v13: the thirteen engines, numbered rings, import by shape, engine panel, Croatian correction off, History picker with accuracy. Android on-device became Whisper on this Mac.

- **Pressable controls highlight** on hover/press, nothing else does: MANTRA_MANIFEST modules/workflow-interface.md, "Pressable controls highlight" (Marko 10.11.2026).

**Copyright footer (10.11.2026):** at the very bottom of the app's Settings, one muted centred line "© 2026 Mantra Productions" (MANTRA_MANIFEST modules/copyright-footer.md).

## TRANSCRIBE A FILE and the local API (v15, 13.11.2026)
Marko, for the MPA Lessons Analyzer: "I want to see this thing open up and it's working". Audio or video of any length, seen working in the window.
- **Window:** History tab, "Transcribe a file…" or drop a file on the window; engine and language pickers beside it (selected engine, AUTO). Table of FILE, PIECE n / N, ENGINE, ELAPSED, TIME LEFT, DONE, a hairline, the words as the pieces come in, STOP.
- **Result** next to the source: `<name>.transcript.json` {"source","engine","language","duration","segments":[{"start","end","text"}],"complete"} and `<name>.transcript.md` (`mm:ss text` per segment); also a History entry.
- **API on 127.0.0.1:8865** (app running): `GET /status`, `GET /engines`, `POST /transcribe {"path","engine"?,"language"?}` (opens the window, returns {"id"}), `GET /job/<id>` (progress, segments so far, output paths). CLI: `"<app>/Contents/MacOS/Voice to Text (Mantra)" --transcribe-file <path> [engine] [lang]` (running app, else headless).
- **Pieces:** ffmpeg mono 16 kHz, 300 s (Cloudflare 60, Google 55, local 180). v14 retry rule unchanged: same engine, next key of the same provider, never another engine by itself.
- **Timestamps from:** Groq (both), Deepgram, AssemblyAI, Speechmatics, ElevenLabs, Soniox. One segment per piece: Gemini, Google v1, Chirp 3, Parakeet, Whisper (this Mac), Cloudflare unless it returns segments.
- Test without touching the window: `curl -s -X POST 127.0.0.1:8865/transcribe -d '{"path":"/full/path.m4a","engine":"groq_turbo"}'`, then `curl -s 127.0.0.1:8865/job/<id>`. A paid engine (Soniox, ElevenLabs) only when picked; a long file on a free engine costs its daily quota (`spend ask`).

## v16-v19 (14.11.2026) and what it taught
- v16: exclusive with Speechify (com.cliffweitzman.speechifymacagent), each closes the other with no loop; the blob stays while the mouse is on it or Settings is open; F1 released at quit; checkAtStart updater.
- v17/v18: accuracy benchmark (12 English sentences via :8837/render; `--bench`, "Benchmark engines" button); two-column Settings, Croatian H and English E, radio per language, % in parentheses. English: Deepgram 88, Groq large-v3 87, AssemblyAI 87. Croatian still TTT's 9.11.2026 figures (no Croatian clips yet). Scoring has no number normalisation ("23" vs "twenty three"), so all % are a little low.
- v19: no-key cards readable. The status strip flips below the pill when the blob is in the upper half.
- Traps: `--settings-shot` offscreen renders show false white areas, check the real window with `screencapture -l`. Swift refuses `var a = "", b = "" { didSet }` (cost a build). A version number once pushed is never reused. Open test windows on the MacBook screen, not the BenQ.
- The site mantravoicetotext.pages.dev is deployed from the Mac with `site/deploy.sh` after copying the release's app.zip to mac/dist/VoiceToTextMantra-v<N>-mac.zip (no compile). Done for v19 on 14.11.2026 (it showed 6).
- Run log: 14.11.2026, v16-v19 built by GitHub, installed, Marko confirmed; site deployed v19.
- Run log: 21.11.2026, v62 bottom ellipse with spectrum built by GitHub (run 44907562969), hook-tested, site deployed v62; waiting for Marko's F1 test and the centre-oval decision.
- Run log: 21.11.2026, v62 bottom ellipse with spectrum built by GitHub (run 44907562969), hook-tested, site deployed v62; waiting for Marko's F1 test and the centre-oval decision.

## v28-v31 (15.11.2026)
- One target box for typing and STYLE (Target.swift): last box clicked/focused in any app, never Vox; AX, then paste with the app in front, then COPY. Terminals are never pasted over by STYLE.
- Two selectors on the pill: language EN/HR/AUTO x text ——— / COR / STY / S+C (12 modes). Settings: quick switches (CORRECTION, STYLING, FRANKFURT, TEST), INPUT/OUTPUT, tabs, engines best first (test of 15.11.2026). Display has TTT's hairline meter.
- Test hooks: notifications .style / .typetext / .mode; defaults testStyleFake; --probe-box <App> [text]. Never open test windows while Marko is dictating (take-open exists).

## v39 (17.11.2026): renamed Vox to Txt (Mantra), the engine dropdown
- App /Applications/Vox to Txt (Mantra).app (executable the same name); bundle id, data folder (Voice to Text (Mantra)), log and :8865 unchanged. The v38 updater cannot take this zip: install by hand once.
- The pill: [EN] [ENGINE] [text mode]. The ENGINE list is best first for the language (accuracy, then speed; paid last, only when picked); the pick = HearEngine.setEngine = Settings' choice. Test hooks: `.engine` (lang, engine) and `.enginemenu` (seconds). Notification prefix com.mantra.voicetotext.

## v39 (17.11.2026): renamed Vox to Txt (Mantra), the engine dropdown
- App /Applications/Vox to Txt (Mantra).app (executable the same name); bundle id, data folder (Voice to Text (Mantra)), log and :8865 unchanged. The v38 updater cannot take this zip: install by hand once.
- The pill: [EN] [ENGINE] [text mode]. The ENGINE list is best first for the language (accuracy, then speed; paid last, only when picked); the pick = HearEngine.setEngine = Settings' choice. Test hooks: `.engine` (lang, engine) and `.enginemenu` (seconds). Notification prefix com.mantra.voicetotext.

## v40-v41 (17.11.2026)
- "Menu item" = the menu bar item's menu. It has History first, then EN/HR/AUTO, then an Engine submenu (best first, same as the pill list; a pick = HearEngine.setEngine), then Correction, Styling. The blob always shows at launch.

## v40-v41 (17.11.2026)
- "Menu item" = the menu bar item's menu. It has History first, then EN/HR/AUTO, then an Engine submenu (best first, same as the pill list; a pick = HearEngine.setEngine), then Correction, Styling. The blob always shows at launch.

## v42-v43 (17.11.2026)
- Engine, correction (style_<lang>), styling (styleButtonOn_<lang>) and text mode (textMode_<lang>) are remembered per language EN, HR, AUTO; AUTO has engine_auto. One getter for every reader.
- Typing only INSERTS (collapse selection, verify, undo): modules/dictation-insert-only.md. Test: two takes in a row.

## v42-v43 (17.11.2026)
- Engine, correction (style_<lang>), styling (styleButtonOn_<lang>) and text mode (textMode_<lang>) are remembered per language EN, HR, AUTO; AUTO has engine_auto. One getter for every reader.
- Typing only INSERTS (collapse selection, verify, undo): modules/dictation-insert-only.md. Test: two takes in a row.

## v44-v45 (17.11.2026)
- Takes are separated by a space (not at the start, after a newline or an opener). A take that did not land: the menu bar item's first click copies it, the next opens the menu (hook com.mantra.voicetotext.notlanded).

## v44-v45 (17.11.2026)
- Takes are separated by a space (not at the start, after a newline or an opener). A take that did not land: the menu bar item's first click copies it, the next opens the menu (hook com.mantra.voicetotext.notlanded).

## v46-v47 (17.11.2026): the take that went away, History, F1/F2
- v43's read-back after typing pressed ⌘Z in WhatsApp Web (Firefox) and removed the take just dictated. Since v46: NO undo or delete after typing; web apps (`Writer.webApps`) get one paste at the caret, native boxes Accessibility; a mismatch is only logged. modules/dictation-insert-only.md rule 3.
- History saves every take (failed, cancelled, quiet ≥1.5 s too) with where it landed; per take: ENGINE, LANGUAGE, [ ] Correction + model, [ ] Styling + model, "Re-transcribe" (correction first, then styling). Thumbs removed; ★ are the engine quality display.
- v47: F1 = English always, F2 = Croatian always (`hotkeyHR`), AUTO never used by the keys; History fills the window; space after a take put before a word; a build's quit waits for the typing (`Typer.inserting`).
- Stress test kit (scratchpad tools of 17.11.2026, rebuild when needed): `say` clips played with afplay through the ADAM into the real microphone; the key as an HID event WITH the fn flag (`CGEventSetFlags(e, kCGEventFlagMaskSecondaryFn)`; Macro Recorder's Send and a plain HID F1 do not reach the Carbon hotkey); the WhatsApp Web box clicked with BiDi real pointer input (a `macro do Click` is undone by the guard's focus restore); box read back by BiDi after 5 s. Turn `duck` off during the test (defaults), `testStyleFake` for the text modes without spending; restore both.

## v48-v53 (17.11.2026): global History, TTT's corrections, the shared database, typing suggestions
- **History is global:** its ENGINE / LANGUAGE / CORRECTION / STYLING are the per-language defaults of the menu bar, pill and Settings (`Slot.*` in Engines.swift). LANGUAGE picks the slot shown. Layout: one NSGridView (rule: MANTRA_MANIFEST modules/alignment.md, "Buttons and controls are always aligned perfectly"). Re-transcribe with STYLING ticked calls the styling Claude: use `defaults write com.mantra.voicetotext testStyleFake -bool true` in tests, delete it after.
- **Test hook `com.mantra.voicetotext.window`** (userInfo tab 0-7, w, h, x, y, row, lang, engine, correction 0/1, styling 0/1): Settings on a tab at a size, a History row selected, History's controls operated. Screenshot with `screencapture -l <window id>`; MacBook screen = x 2560 and up.
- **TTT's corrections** (Corrections.swift, TTT's order): Cyrillic → Croatian dictionary fix → [Claude] → his names → spoken times → the table (pairs.json) → learned rules → the open chat's name (Names.swift). Dictionaries in mac/Resources/dict. Test without the app: `"<app>/Contents/MacOS/Vox to Txt (Mantra)" --fix <en|hr|auto> "<text>" ["<chat name>"]`, `--diff "<written>" "<now>"`, `--sync`.
- **Shared database:** private repo markoboskoauroville/MANTRA_CORRECTIONS (format and merge rule in its TAKEOVER.md); local copy in Application Support/Voice to Text (Mantra)/corrections; this Mac writes only learned/mac.jsonl. Never put pairs, names or learned lines into the public app repo.
- **Typing suggestions** (Suggest.swift): event tap, strip on the blob and the menu bar display, Option+Space takes the first (swallowed only while one shows). Switch `typingSuggestions` (Settings, Typing; menu bar menu). Test with real key events (Quartz, HID tap), read the box back; a click on the strip must be tested with a real pointer click, an Accessibility press does not pass the tap. `--suggest <prefix> [words before]`, `--bench-complete [n]` (his own History sentences, held out), weights for a sweep in `VOX_W`.
- Measured 17.11.2026 (40 held-out sentences, 625 words): keystrokes saved 36.5 % with the first suggestion only, 49.6 % with a pick from the strip; under 10 ms a key.
- Traps: URLSession caches GitHub API answers (stale sha); AppleScript to an app not yet allowed raises a permission dialog (never answer it); test windows open on the BenQ unless moved (Rectangle next-display).

## v54-v55 (17.11.2026): conservative Croatian fix, the local model
- **Croatian fix:** a valid word form is never changed (dictionaries + Hunspell hr_HR from ~/Library/Spelling, class `Hunspell`); one edit only with high confidence. Re-measure after any change: run `--fix hr` over the Croatian takes in History and list `--diff` pairs; the target is zero worse. TTT on the phones still has the old rule.
- **Local model:** `gemma-3-270m-it-Q4_K_M.gguf` in Application Support/Voice to Text (Mantra)/models + `llama-server` (brew llama.cpp); the app runs it on 127.0.0.1:8869 while he types (`LocalModel`, switch `localModel`, file `localModelFile`), stopped after 10 idle minutes and at quit. Measure: start a server by hand (`llama-server -m <gguf> --port 8869 -c 1024 -np 1 --no-webui`), then `VOX_LLM_URL=http://127.0.0.1:8869 VOX_W="llm=40" "<app binary>" --bench-complete 40` (prints all / en / hr). 17.11.2026: 36.5 % → 40.5 % keystrokes saved (EN 39.1 → 43.6, HR 20.4 → 21.5), 14 ms a word. Stop the hand-started server afterwards (testclean does not know it).
- Suggestions stay off in password boxes and terminals: proven with real keys (osascript's hidden-answer dialog; Terminal.app).

## v56-v57 (17.11.2026): the biggest local model
- Default re-ranker: `gemma-3-4b-it-Q4_K_M.gguf` (2,375 MB; 77 ms a word, 2.9 GB of memory while he types, freed after 10 idle minutes); `gemma-3-270m-it` stays as the light choice. Picker: Settings, Typing tab, LOCAL MODEL; pref `localModelFile`, `localModel` false = none. Order when nothing is picked: `LocalModel.preferred`.
- Measured (keystrokes saved, first suggestion; all 626 words / English / Croatian set of 267 words): none 36.6 / 39.1 / 16.5 %, 270M 40.5 / 43.6 / 17.4 %, 1B 41.4 / 44.4 / 17.9 %, 4B 42.6 / 45.5 / 19.3 %. Croatian set: `--bench-complete 40 hr`.
- A model to test goes into a folder beside `models` (not into it) and is served by hand on its own port; delete what is not kept.

## v62 (21.11.2026): the bottom ellipse with a spectrum
- Marko: "small ellipse indicator while I'm recording to come at the bottom of the screen ... a spectral analyzer while I'm talking." `RecordingIndicator.swift`: 150x40 ellipse, bottom centre of the mouse's screen, 20 bars 80 Hz-8 kHz, shown while a take records. Beside v61's TakeHUD oval. Hook: `com.mantra.voicetotext.indicator` userInfo `seconds` (temporary mic session, no take). Proof: `say` into the mic + `screencapture -R` of the bottom centre.

## v63 (22.11.2026): no centre oval
- Marko: "recording blob can go away. Something which is happening in the middle of the screen needs to go away." TakeHUD is deleted; the only indicator is RecordingIndicator (bottom ellipse; paused = frozen dim bars, transcribing = quiet wave). CI pin `.github/ci/no_centre_status.sh`. Never add a window in the middle of a screen.
- v64 (22.11.2026): hook `com.mantra.voicetotext.indicator` userInfo `seconds`, `state` = recording|paused|transcribing (default recording; paused/transcribing need no mic), `screen` = NSScreen.screens index (default: the mouse's screen). Pin: `.github/ci/no_centre_status.sh` has an ALLOWED list of file=count window creations; a new window fails the build.
- v65 (22.11.2026): the ellipse goes to the screen of the text cursor: `FocusScreen.resolve()` = (a) AX insertion point, (b) focused element, (c) focused window, (d) the mouse last; AX y converts with primaryHeight - y - height; re-checked every 0.3 s; log lines `indicator: shown/moved ... by rule`. Hook `screen` overrides; no `screen` = the same rule.
- v66 (22.11.2026): STYLE = StyleChain: Opus (Claude family from Settings) then Groq (openai/gpt-oss-120b via the key ring); refused answers (empty, refusal, preface, much longer, other language, <40 % of the words) go to the next; both fail = box unchanged + reasons in the pill; STYLE becomes UNDO for 30 s. The press ignores the STYLING switch and text mode ---. Log lines `STYLE attempt:` and `STYLE done/NOT done`. `--selftest` runs in the CI. Cause of the old silence: styleButtonOn_<lang>=0 and textMode_<lang>=none refused the press without a log line.
- v67: `"/Applications/Vox to Txt (Mantra).app/Contents/MacOS/Vox to Txt (Mantra)" --stylechain en "<text>" [--groq-only|--opus-only]` runs the STYLE walk with the real providers (no box, no window).
- v68: STYLING switch removed (a press always styles); STYLE keeps sentence order (keepOrder prompt + order check, discordance > 15 % refused). Real-box test recipe: new TextEdit doc on the MacBook screen, AXPress on the pill's button by AXDescription (STYLE; `Undo the last style` for 30 s after a change); Safari textarea needs AXFocused set; Terminal must answer 'does not write into a terminal'. Cost of one styling about $0.004 (Opus 5.5 $4/$20 per MTok).
