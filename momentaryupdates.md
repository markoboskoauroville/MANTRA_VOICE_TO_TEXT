# Requests, word for word

## 1.11.2026

> Please confirm that it works. It is ready to be updated and published on the website as well.

(Asked: Full public release.)

> Please also make a Windows app.

Decided by Marko: free signing on both (Mantra Apps on the Mac with the "open the first time" steps on the site; Windows unsigned with "More info → Run anyway"); Windows in C# .NET + whisper.cpp (Whisper.net), built and tested in the Parallels Windows 11.

> in this app, like in any app which downloads, you just need to always resume downloads. Even if the user closes the application and you open, it will continue where it left off so the user doesn't need to do it again

- The model download resumes: a cut connection retries from where it stopped, and a download interrupted by quitting continues by itself at the next start, from the bytes already there. Mac and Windows. **Status:** Mac done 1.11.2026 (killed at 573,055,166 bytes, the next start went on from that byte, checksum right); Windows done 1.11.2026 (killed at 4,717,622 and 6,918,154 bytes, each start went on from there)

**Status 1.11.2026, 05:05:** published. Website https://mantravoicetotext.pages.dev, downloads on the public release
github.com/markoboskoauroville/mantra-voice-to-text-downloads v1 (Mac 2.2 MB, Windows x64 74 MB, Windows ARM 70 MB),
card 20 on markobosko.pages.dev #/kod. Not yet proven: a real microphone take on either system, Claude in the public
builds, x64 transcription on a real Intel/AMD PC (the VM only emulates x64).

## 1.11.2026 (relayed by the hub session claude-code-d6, Marko's words)

> you need to rename it Voice to Text (Mantra), which is a new rule.

He also stressed the language switch (Croatian | English | auto-detect) as an important part: the page must say it.

- Rename "Mantra Voice to Text" → "Voice to Text (Mantra)": app names (Mac bundle, Windows exe and window titles), the page's title and texts, the release files if renamed, README/TAKEOVER, the bio card. **Status:** done, v2 (1.11.2026)
- The page names the language switch: Croatian | English | auto-detect. **Status:** done (header line, its own card, the keys table)

## 1.11.2026, 05:25

> please rename the one and then close

The rename relayed above: "Mantra Voice to Text" → "Voice to Text (Mantra)", as v2 (whole-number versions); the page's
address mantravoicetotext.pages.dev stays (the link already sent to Damjan keeps working). **Status:** done 1.11.2026, v2 on Mac and Windows, release v2, site and bio card renamed

## 1.11.2026 (relayed by the hub session, Marko's words)

> yes, fix download links so every website gets each new version by itself

- The page's buttons point at addresses without a version (MANTRA_MANIFEST modules/download-always-latest.md); the release step puts each new version behind them and writes the version into the page, in one run. **Status:** done 1.11.2026: Mac download/VoiceToText-mac.zip on the page, Windows releases/latest/download/VoiceToText-win-x64.zip and -win-arm64.zip; mac/build.sh ends with tools/publish.sh (release, page, live check); the old Mac addresses 301 to the new one

## 1.11.2026: speakers down while it listens

> We are continuing to develop our app which is transcribing. It's called Voice2Text, I think. I'm not sure. You will find it. The new feature is it reduce audio output while it's listening to the microphone to 6%. When listening is done, it brings it back to old value.

Marko chose **both** apps (Transcribe Voice to Text RT and Voice to Text (Mantra)).

- While a take records, the system output volume goes to 6%; when the take ends (stop, cancel, ✕, quit, crash) it goes back to exactly the value it had. **Status:** done 1.11.2026 in Voice to Text (Mantra) v3, Mac and Windows (proven 49 → 6 → 49 % and 50 → 6 → 50 %); published 1.11.2026 at Marko's yes ("there is a drop, it works ... push this V3")

## 1.11.2026: one app

> Please unite these two apps. So public one is also my local one and everything is developed under one hood.

- Transcribe Voice to Text RT (Marko's local) and Voice to Text (Mantra) (public) become one app in one repository, MANTRA_VOICE_TO_TEXT; Marko's extras stay in it. **Status:** done 1.11.2026, v3 installed and running; MARKO_TRANSCRIBE is a pointer

## 1.11.2026: every Mantra app in the star

> Not part of the Star menu, so all Mantra apps should be in the Star menu. And the same for this app should be in the Star menu at the same time and also inside the application folder.

- Voice to Text (Mantra) in the star (row repointed, star restarted) and in /Applications (build.sh installs every build); the 11 other (Mantra) apps without a row added; rule in MANTRA_MANIFEST swift-apps.md. **Status:** done 1.11.2026

## 1.11.2026: the start sound before the drop

> Please in this app fix the bug. You need to send the signal that it's recording in normal volume and then reduce the volume. Now when I press F1 I don't hear that it's recording. I need that signal.

- The start sound plays whole at the normal level, then the speakers go to 6 %; the stop sound plays after the level is back. **Status:** done 1.11.2026, v4 installed (the drop waits for the sound's reported end + 0.25 s for the speakers' delay; tested: 69 % held while the sound played, 6 % about half a second after the press, 69 % back before the stop sound); published 1.11.2026 as v6

## 1.11.2026: VT in the menu bar

> please build an icon for the menu bar for this application. It will just be a simple text V and T. I need to see the status of what's going on: - When it's grayed out, nothing is going on. - When I'm talking, when it's recording, then it's red. - When it's processing the recording, then it's yellow. - When it plays the recording again, greatThank you. please build a icon for menu bar for this application that it will be just a simple text B and T and I need to see the status of what's going on when it's grayed out nothing is going on when I'm talking when it's recording then it's red when it's processing recording then it's yellow and when it paste recording again gray

(dictated twice; "B and T" and "plays ... great" are the dictation of "V and T" and "pastes ... gray")

- "VT" in the menu bar: grey at rest, red while a take records, yellow while it is written down / corrected, grey again when it is pasted. **Status:** done 1.11.2026, v5 installed (mac/Sources/MenuBar.swift; all four states seen in screenshots of the menu bar); a click gives Show the blob, Settings, History, Quit; published 1.11.2026 as v6

## 1.11.2026: a red stopwatch while recording

> Please update voice to text. While I am recording my voice for transcription, this VT icon on the bar should become a stopwatch, red stopwatch, which is counting minutes of my talking.

- While a take records, VT in the menu bar becomes a red stopwatch with the time (m:ss) of the take; paused: the same in grey, standing still; after: VT again. **Status:** done 1.11.2026, v6 installed (seen on the menu bar: grey VT → red stopwatch 0:00, 0:04 → yellow VT); published 1.11.2026 as v6

## 1.11.2026, 21:20: is Voice to Text in good shape

> after checking that, please test my transcription application called Voice to Text. Is it running? It's still running. Can it transcribe? Do a few quick tests and report me. Is my application in good shape

- Running? **No** at 21:20: no process, the last log line 14:11 (a dropped take), no crash log. Opened again with --login (v7).
- Transcribes? **Yes**, built-in Whisper in test mode (nothing typed), the Windows test recordings: EN word for word; HR word for word; AUTO chose hr and en right; silence refused ("nothing said"); about 2 s after the model loads on Metal. Tested on v6 and once more on v7. His settings put back (EN, ears = server). — **Status:** done 1.11.2026
- Found: with ears = server and voiced down, the app started voiced.py by nohup, a second copy beside launchd's. v7 kickstarts launchd's agent com.mantra.voiced instead. — **Status:** built and installed 1.11.2026, **not published** (waits for Marko's yes)
- Not tested: the server path (voiced was down; the voice is started only by Marko) and a real microphone take.

## 8.11.2026: the Parakeet engine from TTT into our voice transcription

> There is an application developed right now in the virtual machine, TTT. Well-known application. It is developing now Parakeet: recognition engine with correction for Croatian, everything optimized. So in my local voice transcription engine I want to have the same engine, Parakeet, for fast transcription, with all lessons learned from TTT. Talk with the virtual machine and ask it: is the Parakeet engine ready? If it is ready, you copy it to this computer and use it in our voice application, Voice Transcribe. If it is not ready, ask it to let you know when the tests are finished.

- TTT session (VM_SES5_05-NOV) answered 8.11.2026: ready and usable, tested on the Pixel 7; tests continue, it will message again. Model NVIDIA Parakeet TDT 0.6B v3 int8 ONNX (sherpa-onnx 2.0.1), Croatian correction tools/hr_fix/hr_fix.py with the dictionaries from TTT app/src/main/assets/ime/dict. Lessons: always to_latin() first (Cyrillic output), then fix(); name Marco→Marko; spoken email; times; language choice matters more than engine.
- Plan: engine "parakeet" in MANTRA_VOICE ears.py (so :8837 /hear serves it to every app), model fetched through the Download Monitor into VOICE_ENGINES, hr_fix copied in; then Voice to Text (Mantra) gets "Parakeet EN / HR" among "Who hears you". **Status:** started 8.11.2026

## 8.11.2026: Parakeet in the app

> Yes, I want that especially because it's faster than whisper.

- v8: "Parakeet (fast)" English / Croatian / Auto in ⚙ Transcription model and History, beside Whisper Turbo; 🌐 cycles within Parakeet; always through the MANTRA_VOICE ears (`/hear?model=parakeet`), offered only where they live. First build on GitHub (.github/workflows/build.yml), release v8 Latest on this repo; the public page not touched. **Status:** pushed 8.11.2026

## 8.11.2026: IDLE in the status line, the meter at zero

> In status line, please put the idle. So I know it's idle. And when it fin. This frequens analyser should be at zero, not frozen.

(Said while testing v8 with Parakeet Auto: after a take the bars of the blob stood frozen at the last level and the status line kept "pasted 15 words".) **Status:** started 8.11.2026
- **Cause of the frozen bars:** the old release timer in `endListening()` stopped itself on its first tick, because `recorder.recording` was still true (finish() and cancel() call it before `recorder.stop`), so the bars stayed at the last level. **Done in v9:** the bars go to zero the moment a take ends (`WaveView.reset()`); the status line says `IDLE · F1 TO TALK · …` whenever the stripe is idle, and 3 s after a take finishes (what was typed stays readable that long; a take being written down or a text that did not land keeps its own words). Built by GitHub; not tested with a real microphone yet. **Status:** pushed 8.11.2026
- **Marko's test, 8.11.2026, v9 installed:** "the bars are stop jumping ... everything is working ... it works fantastic." The bars drop to zero after he stops talking, and the status line shows IDLE. **Status:** done 8.11.2026. The public download page stays on v7 until Marko says yes.

## 8.11.2026, 13:10 (Marko, word for word)

Please fix my voice to text up. When it's styling, it adds between paragraph one empty line. Please don't do this. Write everything without spaces between paragraphs.
**Status:** saved first.
**Status (8.11.2026):** v10: prompt rule + Style.noEmptyLines after every styling; pushed, GitHub build next, then installed.

## 8.11.2026, evening (Marko, word for word)

> Please.Fix my voice to text application. Fifth oneSwift one.Uh Bring back assembly AI. Load the API codes from the text file in famous location. And give me options. And remove from drop down menus options. It must be very simple inside settings, which I can access directly on the user interface. There will be a gear icon settings is opening up Correction model and the first is recognition model, or what is the right wording you choose.And then we're going to go Correction model. File pickers for all models which need API keys, but they will be already entered and we using assembly AI from now on.

**Status:** saved first.
**Status (8.11.2026):** v12: AssemblyAI back as the recognition model and the default (English, Croatian, Auto = its language detection held to en/hr; measured 2.2 s on a 3 s clip with key 1 of 24); every recognition model switched to AssemblyAI once, language kept. Keys read by themselves from ~/Downloads/API (AssemblyAI-api.txt, Claude.api.txt) at launch and whenever ⚙ opens. The gear on the pill opens ⚙ directly (the drop-down menu is gone). ⚙: 1 hotkey, 2 Recognition model (round buttons: AssemblyAI / Whisper Turbo / Parakeet, Language EN / HR / Auto), 3 Correction model (None / Haiku / Sonnet / Opus, and the STYLE button's Claude), 4 API keys (count, File…, Test). Pushed; GitHub build next.

## 10.11.2026 (Marko, word for word, via the master session task 87)

> Please upgrade my local app, my voice-to-text app, to have the same features as my TTT app for voice transcription with all these models and everything. Same copy.

**Status:** saved first.

## 10.11.2026, rule for TTT that applies here too (Marko, word for word, relayed by the master, task 87)

> If it doesn't pass after some time make a break of three seconds and try again ... If key is exhausted, go in the next key of the same provider. Change models automatically never do that.

**Status:** saved first. v14: no fallback to other engines; network error or timeout: wait 3 s, retry the same engine up to 10 times with the status shown, then stop with the take kept in History; quota or refused key: next key of the same provider only.

## 13.11.2026: transcribe a file, seen working (from the MPA Lessons Analyzer, MPA request 256)
Marko: "please use star menu item for this. I have my blog for transcribing my own voice, and there are many different algorithms and APIs and use that, and I want to see this thing open up and it's working"
**Status:** saved first (read as: Voice to Text (Mantra) gets "Transcribe a file…" (open + drop, video or audio, any length: split into pieces, engine chosen from its rings, progress on screen, timestamped segments saved next to the file) and a local API, so the MPA Lessons Analyzer and Queen can ask it; the 46-minute class of 12.11.2026 is its first file. The voice API :8837 timed out on it.)
**Status (13.11.2026):** v15 built by GitHub Actions (run 43396564171, green), release v15 Latest, asset app.zip; API on 127.0.0.1:8865, flag --transcribe-file. Not installed yet, not yet run on the 46 minute class.

## 13.11.2026: default engine Groq large-v3, three free accounts
Marko: "for transcribing anything now, its default engine is Grok, a large model of Whisper. I think it's v3. Over 3 accounts, not a paid one, by rotating the API keys of 3 accounts" / "3 eq freee"
**Status:** saved first (read as: the selected engine by default = groq_v3; its ring = the keys of his 3 free Groq accounts, rotated forward on quota; also the default of "Transcribe a file".)

## 14.11.2026: Speechify and Voice to Text exclude each other (via the master session)
> fix my opposite engine, which is voice to text. I have two engines. I'm using Speechify, which is from Speechify, or my own thing. They're both supposed to register F1 as a transcription key, and after transcription, they disappear. But if I catch it with the mouse, they don't disappear, because I want to change the settings. The idea is that one replaces the other. If I open my own engine, voice to text, then it closes Speechify automatically. If I open Speechify manually, my own engine disappears. So they are mutually exclusive.

**Status:** saved first.
**Status (14.11.2026):** v16 built by GitHub Actions (run 43591642705, green, first try), release v16 Latest; installed, signed Mantra Apps. Opening ours closed Speechify; opening Speechify closed ours, no loop. Hover hold and F1 dictation wait for Marko.

## 14.11.2026: accuracy benchmark of the engines, and the status strip that flips (via the master session)
Marko, word for word:
> Now please test the engine as we already do on my phone for accuracy. Invent 12 sentences and then see how accurate this engine is doing the work and then next to each engine in parentheses put the percentage of correctness.

> for voice to text, this display at the top, when I'm dragging the icon, when I pass the half screen up, this display going to the bottom. When I pass down, it's at the top as it is now. So when I push it off the screen, I can only see this status part.

**Status:** saved first.

Marko, 14.11.2026, added (word for word):
> It's same as we have in TTT in settings, voice to text, mantra. Make two columns. Radio buttons to select the actual engine for each language plus look at TTT and get its design here. I want the same menu design as in TTT to have it here in my voice to text mantra. This is a new modern design we have.

**Status:** saved first (read as: the engine panel in Settings gets two columns, one per language, a radio button per engine picks the engine used for that language, in TTT's modern look).
**Status (14.11.2026):** DONE in v17 (run 43605113038, green) and v18: benchmark, two-column cards, flipping strip; see TAKEOVER.

## 15.11.2026: Frankfurt route for every engine (via the master session)
Marko, 15.11.2026, word for word:
> Please update my voice to text application so it also goes to Frankfurt and it needs to have all the engines it has it very good

**Status:** saved first. Read as: the audio goes to the ttt-relay on chromium-vm (Tailscale 100.102.86.30:8897), which calls the engines from Frankfurt; every engine the app has that can run in the cloud works through it, the direct path stays as the fallback; a FRANKFURT switch in the engine panel; the route shown per take.

Marko, 15.11.2026, added (word for word):
> Also I have two application, one is voice to text and another is voice engine. And they both have same icon so I am confused. Let the voice to text be red icon and let the engine be green icon.

**Status:** saved first. Read as: Voice to Text (Mantra) gets a red icon in v20 (Dock, Finder, menu bar consistent); the Voice Engine gets green separately.

## 15.11.2026: make Frankfurt visible (via the master session)
Marko, 15.11.2026, word for word:
> How will I know that my voice to text is now going through Frankfurt? How will I know that? I don't see anywhere the indication.

**Status:** saved first. v22: FRA / DIR badge beside VT in the menu bar, a 2 s toast after each take with the route, and the Settings window header showing "Route: FRANKFURT ✓ (relay v2 answers)".

## 15.11.2026: Talk Mode uses this app's engines (via the master session)
Marko, 15.11.2026, word for word (said about Talk Mode (Mantra)):
> So, talk mode is there. It needs to use my engine basically, voice to text, the same one I'm using for transcription, and of course voice engine for talking.

**Status:** saved first. v23: the local API (127.0.0.1:8865) gets `POST /hear?lang=en|hr|auto` with a WAV body: the engine picked for that language, the same route as F1 (Frankfurt, key ring, retries), the corrections, no styling, nothing typed. Talk Mode (Mantra) v4 sends every utterance there.

## 15.11.2026: how good and how fast each engine is, in the engine name (via the master session)
Marko, 15.11.2026, word for word:
> Please now update how good is each engine and how fast is each engine in the engine name everywhere.

**Status:** saved first. Voice to Text v24 keeps per-engine median time (last 20 takes, per language) and a quality score (WER against a reference phrase in TEST mode, or Marko's rating) and shows "Deepgram · 1.0 s · ★★★★☆" wherever an engine name appears; Talk Mode v5 reads it from /engines.

## 15.11.2026: Talk Mode as the remote control of the engines (via the master session)
Marko, 15.11.2026, word for word (his message was cut off at the end):
> I want to have luxurious changing of engines, it's basically will be remote control for our VOX application, audio to text, but in this app, talk mode, I want to have this option, it means I have the stars ratings, timing and everything, and the credits and…

**Status:** saved first. v26: `GET /engines` also says `selected_en`, `selected_hr` and `credit` (keys in the ring, free audio of the window, used here, left, price per hour, Frankfurt), from this Mac's own records; `POST /engines/select {"id","lang"}` sets engine_en / engine_hr exactly as a card in Settings, and Settings repaints. Talk Mode (Mantra) v8 has the ENGINES panel.

## 15.11.2026: Magnetic detach of the display and the body (v27)
Marko, 15.11.2026, word for word:
> can we please do our updating of this application, I call it Vox Voice to Text. and idea is because voice to text has two parts, there is a small display at the top and the body I want to be able to long press the small display or the body, whatever long pressing and then they detach imagine like a magnet which gets deactivated and then I can move each piece separately and when I bring them together they again attach as two magnets because I want to have this small display around the screen available in front of my eyes and a big one somewhere on the side. So can we make this magnetic thing trick now please?

**Status:** saved first (15.11.2026).

## 15.11.2026: STYLE must never freeze (v27, with the magnet)
Marko, 15.11.2026, word for word (via the coordinator):
> Please fix the bug. There is a style icon there ... When I click on the style ... if there is nothing to be changed the application is freezing. It should try only for 2 seconds. In that time it needs to check if there is a box to change and try to change. If there is no box and it couldn't change it shows that with red color. So coloring sequence is the next one. It's grey. I click style. It is yellow, meaning it's searching for box and changing it. If it's not successful, it become red and again grey. When it's successful, it become green and then grey. ... It tries few seconds and then quits. and I can manually try again ... No blockage of the app whatsoever.

**Status:** saved first (15.11.2026).

## 15.11.2026: Vox v28: find the text box for typing and STYLE, nine modes, Settings in tabs
Marko, 15.11.2026, word for word (via the master session):
> Our application, which we call Voice to Text, is still buggy. If there is a text box on the screen that I selected, sometimes it doesn't find it. When I press Style, it also doesn't find it. You need to reinforce scanning the screen for what is under the mouse pointer and target the text input box for both functions, Style and transcription. If I click on a text box and then click on Style, of course it should write into the last text box I clicked on. Please make finding text boxes and restyling really possible. On the left side there are English, Croatian and Auto. So these are 3 modes, right? But we need 9 modes. So there will be 2 selectors. Next to Auto, Croatian and English comes Styling, Styling plus Correction, and Correction only. Correction means correcting spelling mistakes, Styling means correcting style, and Styling plus Correction corrects both. That way I can quickly switch modes from the user interface. When I open my settings, it's a huge window with many things, and what is at the bottom is difficult to even access. So we need to think about how to organize this so it is easy to access and understand. Again, I think you need to go with tabs. Maybe the engines should also be grouped, by Whisper, because we have a few Whisper providers, then Google engines, and so on. Please organize the settings better, but finding the box where to type and where to style is very important. Pressing Copy is just the last resort if nothing else works.

**Status:** saved first (15.11.2026). v28: one target engine (the last text box clicked or focused in any app, kept while Vox has the focus) for typing and STYLE, AX write then paste then copy; LANGUAGE (EN · HR · AUTO) x TEXT (STYLE · STYLE+CORRECT · CORRECT); Settings in tabs, engines grouped by family.

## 15.11.2026: the display's hairline VU meter, engines ordered by quality (with v28)
Marko, 15.11.2026, word for word (via the master session):
> This is for voice to text. The same as we have in our TTT. This small display which I can detach, the small display at the top, needs to have hairline Vometer at the bottom. Please make that possible. Please order the engines inside the settings by the quality. At the top are the best ones from our test and down there are the worst ones.

**Status:** saved first (15.11.2026). The display gets TTT's hairline meter (MaRecordMeter.kt look) along its bottom edge, live while recording; the engines in Settings ordered best first by the test of 15.11.2026 (Groq large-v3, Whisper this Mac, Gemini, Chirp 3, Groq turbo, Cloudflare, AssemblyAI, Deepgram, Speechmatics, Parakeet, Google v1; Soniox, ElevenLabs untested last), families ordered by their best member; the stars seeded from that test.

## 15.11.2026: the TEXT selector's empty choice (with v28)
Marko, 15.11.2026, word for word (via the master session):
> The switch in the blob, correction, styling, styling plus correction. I am missing empty thing, maybe just minuses, three minuses. Because sometimes I don't want either of these.

**Status:** saved first (15.11.2026). A fourth TEXT mode "———" (AX "No styling or correction"): the words as the engine heard them, nothing changed. Order ——— · COR · STY · S+C; 3 languages x 4 text modes = 12; the default stays Style + Correct.

## 15.11.2026: quick switches at the top of Settings (with v28)
Marko, 15.11.2026, word for word (via the master session):
> In the settings, I need to have quick switches at the top, MAC switches. And these switches are basically telling me for correction and styling which model are used.

**Status:** saved first (15.11.2026). Above the tabs, always in sight: CORRECTION (auto correct after each take) and STYLING (the STYLE button), each a macOS switch with its Claude model picker, the model id really called and its last time; FRANKFURT and TEST as switches too.

## 15.11.2026: INPUT and OUTPUT under the quick switches (with v28)
Marko, 15.11.2026, word for word (via the master session):
> Under that, two drop-down menus, input and output. Input is which microphone, output is which speaker.

**Status:** saved first (15.11.2026). Under the quick switches: INPUT (the microphone Vox records from, saved) and OUTPUT (the speaker for Vox's own sounds: start/stop, the magnet's pop, History playback; the system's default output is never changed), both following devices plugged in or out.
