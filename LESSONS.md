# Lessons

## v60 (21.11.2026): ducking and the end sound
- Never restore the ducked speakers before the end sound: v57 and v58 called Duck.up in endListening and again in recorder.stop, so the music was back at full level under the beep and Marko did not hear it. The end sound plays while still ducked, then a pause, then a smooth ramp.
- One owner for the duck: Duck.hold blocks every other Duck.up during the end sequence; down() cancels a running ramp. Only quit and launch force a restore.
- Log the order of sounds (`sound:` and `seq:` lines) before guessing which sound moved; the v57 to v58 diff showed the end sound never changed.

## v58 (21.11.2026): the spoken Go
- Marko's dictated voice names are garbled ("batteries" = Beatrice): look in the memory files (djmantra-tester-voice-say) before asking.
- langsay exits silently while VOICE ENGINE is off, so its functions cannot be imported for a one-off render; call Speechify directly with the key ring by shape (the first key answered 402, the next worked).
- A cue that must not be recorded is solved by order, not trimming: play, wait for the end callback, then open the mic; guard a second key press while it plays. Rendering "Go." gave 0.91 s with silence; trimmed to 0.35 s.
- To delete a folder of test files, make a fresh folder instead of rm -rf * (the safety check refuses it); ditto over /Applications replaces an app without rm.

## v56-v57 (17.11.2026): the biggest model
- Measure before deciding by arithmetic: "4x the size = 4x the time" said the 4B model would miss 150 ms a word; measured it was 77 ms (1B: 28 ms). Bigger models run closer to the GPU's real speed.
- Bigger was better at every step, but by one point each (40.5 → 41.4 → 42.6 % of keystrokes saved) for 3x and 10x the file and 5x the memory: say the price (2.9 GB while he types) with the gain, and leave a picker.
- A Croatian test set must be built on purpose: 40 newest sentences held 86 Croatian words; all of History held 267. Takes made on AUTO count by what they are.
- Test files go in a folder the app does not read (models-test): the app took the first .gguf by name, so a test download would have become the default by itself.
- The model's weight in the ranking depends on its size: sweep it per model (270M best at 40, 1B and 4B at 60).

## v54-v55 (17.11.2026): the conservative Croatian fix, the local model
- A 75,000-word dictionary does not know Croatian's word forms: "not in the dictionary" is not "wrong". Validity needs the spelling dictionary with its endings (Hunspell hr_HR: stem + suffix rules, two levels, the naj- prefix); 150 lines of Swift read it. macOS's own spell checker has no Croatian even with the files in ~/Library/Spelling.
- A correction in dictation must be near certain: no change to a valid form, no edge letters, no ending vowels, a clear margin over the next candidate. Fewer fixes, none worse. "mesec" after "WhatsApp" was "message", not "mjesec": context decides, and without support a short word is left alone.
- Prototype the rule in Python on his real takes first (ten minutes, no build), then write the Swift once.
- A 270M model as a RE-RANKER (one call a word for the next word's likeliest first pieces, added to the n-gram score) gave +4 points of keystrokes saved in English at 14 ms a word; as a generator it would be slow and wrong. Its Croatian is weak: measure the languages separately, the sum hides it.
- llama.cpp's server with cache_prompt answers an extended context in 14-25 ms; the first call is 100-200 ms. Ask when the word ENDS, not at each key.
- brew install llama.cpp switched the unversioned openssl links to openssl@4: say so when a brew install changes links.
- `osascript … close document` can hang behind an app's popup: run it in the background and kill it after a few seconds, then check the window list.

## v48-v53 (17.11.2026): one grid, TTT's corrections, the shared database, typing suggestions
- A group of controls is ONE NSGridView, never rows built one by one: a check box with its own title beside a labelled pop-up can never line up. Fix the label column's width, or the grid gives the free width to the labels and the pop-ups stay narrow at a wide window (v48 did).
- "Global" has to be read from the code: the menu's Styling tick is the STYLE button's switch (styleButtonOn_<lang>), not the text mode. History now shows the same tick, so Re-transcribe with it on calls the styling Claude.
- A page built for 840 pt leaves an empty column in a wide window: give the page the window's width and let paragraphs wrap at it (preferredMaxLayoutWidth 0 + a width constraint), never a fixed wrap width.
- URLSession's cache reuses a GitHub API answer for 60 s: a tree read right after a push carries the old sha and the next PUT is refused (409). `cachePolicy: .reloadIgnoringLocalAndRemoteCacheData` on every API call.
- One file per device in a shared data repo: append-only lines, each device writes only its own file, merge = union. No push can lose another device's work and there are no conflict files (TTT's whole-file sync has them).
- TTT's release build is not debuggable: `adb run-as` cannot read its files. What the phones learned reaches the Mac only when TTT pushes it.
- WhatsApp Web tells the name itself: the message box's accessibility description is "Type a message to <name>". Read the box, not the page.
- The chat's name passed to the engine as a keyword is stronger than any fix afterwards: with keyterm "Vasyl" Deepgram wrote the contact's spelling by itself; without it the same clip came back as "athlete".
- A box that empties when the message is sent cannot be read at the next take: look at it every few seconds while it still resembles the take and keep the last look (TTT has the IME's own field for this; the Mac has only Accessibility).
- An event tap sees the mouse click BEFORE the button under it: clearing the suggestions on every click made a click on a suggestion do nothing. An Accessibility press does not go through the tap, so that test passed while the mouse failed. Test with what he uses.
- Key events posted for a replacement need their own mark (eventSourceUserData) so the tap does not read them back, a private event source and empty flags (he is still holding Option: Option+Backspace deletes a whole word).
- Do not offer corrections for a word that common words still begin with: he is not wrong, he is not finished.
- Weights guessed by feel were 1 point of keystroke saving below the measured ones; an environment variable (VOX_W) made a sweep possible with no build. The plateau (36.5 % with the first suggestion, 49.6 % with a pick) is the n-gram ceiling; more needs a neural model.
- MaCroatianFix changes correct but rare forms when a commoner neighbour fits the context (opciji → opcija, stvarom → stvaram): on 23 of his recent Croatian takes 9 changed, most for the better (objeviti → objaviti, mesec → mjesec), about a third not. It is TTT's behaviour, ported as it is; the tick on the Text tab turns it off.
- AppleScript to an app the terminal was never allowed to control raises a macOS permission dialog (CotEditor, 17.11.2026): open a scratch file with `open -a` and use Accessibility instead; never answer the dialog.
- A test window opens where the app last was: check its x and send it to the MacBook screen with Rectangle (`rectangle://execute-action?name=next-display`) before testing.

## v46-v47 (17.11.2026): the take that went away
- NEVER auto-undo after typing. A read-back of a web box (WhatsApp Web's Lexical editor in Firefox, any contenteditable) is late and normalised (NBSP, paragraphs), so "the box is not what I expected" is not evidence that something was replaced. v43 pressed ⌘Z on that guess and removed the take Marko had just dictated, twice per take. A check after inserting may log or warn, never delete.
- Web pages get one paste at the caret: the page's own editor handles ⌘V like his own; Accessibility writes into a DOM editor behind its back.
- A test that only uses the test hook (`.typetext`) misses timing and focus; the real path is F1, the microphone, the engine, then typing. The stress test now plays `say` clips through the ADAM into the real microphone.
- Synthetic keys: Macro Recorder's `Send "{F1}"` does not reach a Carbon hotkey (it posts to the app); an HID F1 without the fn flag is not caught either; with `kCGEventFlagMaskSecondaryFn` it is (fnState = 1 on this Mac).
- `macro do` restores his app, field and caret after it runs: a `Click` into a box through the guard is undone right after; click inside Firefox with BiDi real pointer input instead.
- A build's quit must also wait for the typing, not only the recording and the engine: `busy` was false between the words and the paste.
- NSStackView's default distribution leaves room at the trailing end: two panes that must fill a window need `.fill`, a low hugging priority on the wide one and a share constraint, never a fixed width.

| take | app | lang | mode | key | landed | still there after 5 s |
|---|---|---|---|---|---|---|
| 1 | WhatsApp Web (Firefox) | EN | none | F1 | yes (pasted) | yes |
| 2 | WhatsApp Web | EN | COR | F1 | yes, space before | yes |
| 3 | WhatsApp Web (back to back) | EN | STY | F1 | yes | yes |
| 4 | WhatsApp Web | HR | none | F1 | yes | yes |
| 5 | WhatsApp Web | HR | S+C | F1 | yes | yes |
| 6 | WhatsApp Web | HR | COR | F1 | yes | yes |
| 7 | WhatsApp Web | HR | STY | F1 | yes | yes |
| 8 | WhatsApp Web, caret in the middle | EN | none | F1 | yes, inserted there | yes |
| 9 | WhatsApp Web, a word selected | EN | none | F1 | yes, the word kept | yes |
| 10 | TextEdit, caret at the start | EN | none | F1 | yes, glued ("rehearsal.Existing", fixed v47) | yes |
| 11 | TextEdit | EN | COR | F1 | yes (Accessibility) | yes |
| 12 | TextEdit (back to back) | HR | none | F1 | yes | yes |
| 13 | WhatsApp Web, v47 | EN | none | F1 (stored HR) | yes, Deepgram EN | yes |
| 14 | WhatsApp Web, v47 (back to back) | HR | none | F2 | yes, Groq HR | yes |
| 15 | TextEdit before a word, v47 | EN | none | F1 | yes, "dog. We" | yes |
COR/STY/S+C ran with testStyleFake (no Claude call). Not tested: a second native app (a click without the guard was refused), Claude desktop and Chrome boxes, Marko's own voice and fingers.


## v28-v31 (15.11.2026)

- The front app's focused element is the wrong question once Vox has been clicked or its Settings is in front: remember the last box from the focus observer and the clicks of other apps (a global monitor never sees clicks on Vox itself, which is exactly right).
- A paste fallback is only as safe as the box it trusts: a terminal's AXTextArea is its whole screen, so STYLE must never ⌘A ⌘V there. Keys go only while the box's own app is frontmost (checked right before each key).
- Marko uses the app while it is being tested: a test that activates TextEdit took his focus in the middle of his take (13:20, 15.11.2026). Tests that need the front app wait for him; `--probe-box` answers "AX or paste" without the front.
- Additions arriving while a run is green cost one version number each; batch them before the push when possible.
- `TextMode.none` would read as Optional.none in comparisons: name the case `plain` with rawValue "none".

## v27 (15.11.2026)

- A drag that records the window origin at mouse-down breaks when the press itself moves or re-parents things (the long press detaches the display mid-press). Drag by increments (origin plus the mouse delta since the last event) and any part can change under the finger.
- A borderless panel with no fill lets clicks through its clear pixels: the detached display's panel is clear, so only the band needs a hitTest; the body's panel needed the 1 % fill for the opposite reason.
- A still press must never attach: the detached display steps 30 pt from its slot (more than the 24 pt snap) and attaching needs a real drag (`didDrag`).

## v16 (14.11.2026)

- Two apps that want the same key must be told apart by who starts: ours closes Speechify only at its own start and remembers those pids; the launch watcher ignores them, so the two rules never chase each other. Speechify's own app is the agent com.cliffweitzman.speechifymacagent; the splash closer (community.auroville.speechifysplashcloser) is ours and must not match, so the match is the prefix com.cliffweitzman.speechify.
- Release the hotkey explicitly before terminating; do not rely on process death when the quit is a hand-over.
- An auto-hide that only looks at a timer hides under his mouse; check NSEvent.mouseLocation against the blob's frame (and the settings window) when the timer fires and look again 1.5 s later.

## v15 (13.11.2026)

- Transcribing a file is the same adapters with their own timestamped answers, not a second program: `Stamped.swift` repeats the calls of `Adapters.swift` with `verbose_json`, `utterances=true`, AssemblyAI's `/sentences`, Speechmatics `json-v2`, so a change to a request has to be made in both files.
- The pieces are cut by length, not at silence, and not overlapped: a word that falls on a cut can be split between two pieces. If that shows in a real lesson, cut at the quietest second near the boundary (ffmpeg silencedetect) instead of adding overlap.
- Local engines (Parakeet, Whisper on this Mac) read a file, not bytes: their pieces are written to a temp WAV; the 46 minute MPA class timed out the voice API in one piece, so those pieces are 180 s.
- The window is a drag destination through its content view (`DropBox`), not through the table or the text views: a text view takes the file path as text.
- The API answers only a Host of 127.0.0.1 or localhost (a web page must not be able to start a job through DNS rebinding) and binds the loopback address only.

## v13 (10.11.2026)

- A closure with explicit arguments cannot use `$0` inside a nested closure (the build said "anonymous closure arguments cannot be used"): write the loop out. The Mac is never compiled here, so every such slip costs a GitHub run; read the code twice before the push.
- Deepgram's `detect_language=true` put a Croatian sentence into Slovak; `language=multi` heard it right. Its `detect_language=hr&detect_language=en` is a parse error. Speechmatics takes `"language": "auto"` and refuses `language_identification_config`. Measured with curl before the code was changed, one free job each.
- Speechmatics AUTO on a 5 s clip came back "Language identification could not identify any language with sufficient confidence" (the job is accepted, then rejected at the status call): its AUTO falls through to the chain; fix later by running en or hr from the other engine's language.
- The file the keys come from is read by name: ~/Downloads/API holds GitHub tokens, Twilio, Tailscale. Only files whose names say a speech or Claude provider are opened, and a key that failed its free test is remembered by fingerprint so it is not asked again at every launch.
- Google keys are two keys in one: an AIza key is tested as Gemini and as Speech v1 and goes into each ring that answers. A service account is a JWT signed RS256: Security needs the PKCS#1 inside the PKCS#8, so the DER header is walked and skipped.
- Settings grew past the screen with the 13-engine panel: the page scrolls (a flipped document view), widths 280 / 190 / 220, minimum window width 800.

## v4 (1.11.2026)

- A sound asked to play is not yet out of the speakers: v3 dropped the volume 0.15 s after `play()` of a 0.1 s sound,
  and Marko heard nothing (the ADAM over USB starts it later). Wait for NSSound's didFinishPlaying, then 0.25 s more.
  And put the level back before the stop sound, never after it.

## v3 (1.11.2026)

- A framework-dependent Windows build started by `prlctl exec` without DOTNET_ROOT shows Windows' "install .NET" dialog
  and looks like a hang (no log line at all). The VM's .NET is C:\dotnet: set `$env:DOTNET_ROOT` in test scripts, or
  test the published self-contained exe.
- COM interop for IAudioEndpointVolume: every method `[PreserveSig]`, the event-context GUID as
  `[MarshalAs(UnmanagedType.LPStruct)] Guid` (it is a pointer in C).
- The star reads its rows only at launch: a changed row means a restart of Star (Mantra).

## Mac (1.11.2026)

- **whisper.cpp HEAD did not run on Metal under macOS 15.0**: the runtime Metal compiler rejects `constexpr` on the
  bfloat casts in `ggml/src/ggml-metal/kernels/unary.metal`, the library fails, the BLAS fallback then aborts inside
  `whisper_init_state` (the whole app dies). One-line patch (`mac/whisper-metal-macos15.patch`); and a crash during a
  load now makes the next start use the processor (`loadingModel` / `cpuOnly`).
- **Build portable:** `-DGGML_NATIVE=OFF` (the first build was `-mcpu=native`), and `-ffile-prefix-map` so the binary
  does not carry /Users/<name>/… paths in whisper.cpp's assert messages (found with `strings` before publishing).
- **Cloudflare Pages refuses files over 25 MB**: the 70–74 MB Windows zips went to a public GitHub release in a
  downloads-only repository (README + zips, no code, so no history to scan beyond one commit).
- **Gemini pictures from Claude in Chrome**: Gemini's page blocks fetch and form posts to localhost; the extension's
  `zoom` with `save_to_disk` on the image pinned at its natural size gives the exact pixels (crop the top-left w×h).
- **Testing a resumable download costs almost nothing**: seed the `.part` from the local model (`head -c`), kill it
  mid-way, start again, compare the checksum; 14 MB of the SIM instead of 547.
- **build.sh's "is it running" test missed a copy started with `--login`** (`pgrep -f '…RT$'`), so v29 was installed
  under a running v28 (MARKO_TRANSCRIBE, fixed: `( |$)`).


## Windows (1.11.2026)

- **whisper.cpp on Windows needs the Visual C++ runtime** (msvcp140.dll, vcruntime140.dll, on x64 also
  vcruntime140_1.dll). A clean Windows 11 (the Parallels VM) did not have it: Whisper.net said only "Failed to load
  native whisper library ... The operation completed successfully". The app now checks for the three DLLs itself and
  says "Whisper needs the Microsoft Visual C++ runtime: ⚙ → Settings → Get it" (a link to Microsoft's vc_redist for the
  machine's architecture). `vc_redist.exe /layout` does not unpack the DLLs, so they are not shipped app-local.
- **Single-file publish hides Whisper.net's DLLs.** They come as `runtimes/<rid>/*.dll` content, not as native assets:
  with only `IncludeNativeLibrariesForSelfExtract` they were bundled and never extracted ("Native Library not found in
  default paths"). `IncludeAllContentForSelfExtract=true` extracts everything once to `%TEMP%\.net\MantraVoiceToText\…`
  and Whisper.net finds them there.
- **x64 under Windows-on-ARM emulation has no AVX** (this VM, Windows 11 26100): the plain Whisper.net.Runtime refuses
  ("AVX is not supported ... install Whisper.net.Runtime.NoAvx"). The NoAvx runtime (2.5 MB) is now in, so old x64 CPUs
  and emulated x64 work; real x64 PCs with AVX use the fast one by themselves.
- **Unicode SendInput garbles Windows 11 Notepad**: "Hello, this is a test" arrived as "Hello, ......" (fast) or
  "Hello,      is a test.ooatian:" (one key every 5 ms). Clipboard + Ctrl+V is exact, so typing is the paste.
- **Saving the whole clipboard can take 30 s**: asking a DataObject for every format makes Windows render each one
  (in Parallels the shared Mac clipboard answers slowly). Only the text formats (Unicode, RTF, HTML) are saved and given
  back; the paste took 0.5 s after that. Parallels shares the clipboard with the Mac, so every test paste briefly passes
  through the Mac's clipboard too.
- **A layered WPF window is not in a GDI screenshot.** `Graphics.CopyFromScreen` without CAPTUREBLT misses the blob;
  with CAPTUREBLT the VM returned a white screen. Windows' own Win+PrtScn (into Pictures\Screenshots) shows it.
- **Invoking a blob button through UI Automation moves the focus** away from the app being typed into (Notepad lost
  the foreground). A real click should not (WS_EX_NOACTIVATE + MA_NOACTIVATE; not yet proven with a real mouse), so STYLE was tested with the app's own
  `--press style <s>` switch, which calls the button exactly as a click does.
- **Windows Terminal's text area is "Text", not "Edit"**, for UI Automation; terminals take Ctrl+V, so the
  CASCADIA_HOSTING_WINDOW_CLASS / ConsoleWindowClass windows count as text boxes.
- **The Parallels VM suspends itself** a few seconds after the last `prlctl exec` client disconnects (sometimes during
  a long one). A background `prlctl exec "Windows 11" powershell -Command "Start-Sleep 3600"` keeps it awake while
  testing; `windows/tools/vmx.sh` resumes it before every command.
- **Speed in the VM:** large-v3-turbo q5_0 on 4 virtual ARM cores of the M1 Pro (CPU only, NEON) needs about 35 s for a
  7.5 s take, warm or cold, flash attention or not: the encoder always works on a 30 s window. A real PC with more
  cores, or a GPU runtime (Vulkan / CUDA, not added), will be much faster; this is the first thing to improve.
- **The model download resumes from the .part** (Marko, 1.11.2026: "always resume downloads"): proven by killing the
  app twice during a download; each new start logged "starting at <the .part's size> bytes (Range: bytes=…-)" and the
  bytes matched the real model. Test it with a few MB only (SIM data) and put the real file back (`tools/dltest.ps1`).

## Downloads (1.11.2026)

- **Cloudflare Pages answers HEAD on a zip without Content-Length** (`curl -sIL` gave 200 and no length), so a size check
  by HEAD always failed for the page-hosted Mac zip; publish.sh fetches small files whole and compares the sha256, and
  uses HEAD only for the GitHub assets, which do send the length.
- **The SEO kit writes the old downloadUrl until it runs**: a "no versioned address left" guard placed before
  seo_app_page.py tripped on the previous deploy's JSON-LD. The guard goes after the SEO step.
- **`gh release upload file#label` sets only the label, not the asset name**: a fixed asset name needs the file itself
  copied to that name (publish.sh does it in a temporary folder).
- **Cloudflare `_redirects` accepts a splat mid-name** (`/VoiceToTextMantra-* /download/VoiceToText-mac.zip 301`) and
  redirects only paths with no file behind them, so deploy.sh removes the old versioned zips from site/public.
- **`set -o pipefail` + an empty grep inside `$( )`** ends a script silently: the first live check stopped without a word;
  `|| true` on the parsing lines.

## 1.11.2026: zsh does not split words

A test loop `for run in "whisperHR hr-test" …; do set -- $run` passed the whole string as $1 under zsh (no word splitting
of unquoted variables): the app got `.wav` and an unknown `hear`, and answered "nothing recorded" four times. It looked
like an app failure and was mine. Pass the two values as separate arguments to a function.

## 14.11.2026: Swift refuses `var a = "", b = "" { didSet }`

A stored property with an observer must be a declaration of its own: "var declarations with multiple variables cannot have explicit getters/setters". It cost a GitHub run (the Mac may not compile). A tint drawn with alpha over "nothing" looks right only on the colour behind it: paint the card colour first, then the tint. A benchmark with spoken numbers is scored without number normalisation (TTT's way): "23" for "twenty three" counts as wrong, so everyone's % is a little low.

## 15.11.2026, v20: Frankfurt
- One relay, two clients: ttt_relay.py serves TTT and this app, so a change for one (AUTO for the Mac) is additive for the other (lang en/hr unchanged, VERSION 2); the phone's key order is never replaced by the Mac (`replace:false`, whole credentials only when the relay has none).
- "Direct as fallback" is only for a relay that does not answer; a relay "failed" is the engine's verdict (TTT rule 11: never another engine/route by itself after the relay has rotated and retried).
- Hear.used must stay "Engine LANG" (History matches it); the route has its own field Hear.route.
- ATS applies to IP addresses since macOS 11: a plain http://100.x relay needs an Info.plist exception, else URLSession fails silently and the direct fallback hides it. Test the route, not only the build; the harmless fallback must say why (v21).
- A pushed version number is never reused: a diagnostic commit under v20 built but made no release.

## v33 (16.11.2026)
- A view lives in one superview only: the display (BandField) is built once and moved between the blob, the magnet's panel and the status item's button; `passThrough` hitTest nil lets the status button take the click and show the menu.
- A status item's place cannot be forced: autosaveName plus "NSStatusItem Preferred Position <name>" = 0 gives the slot nearest the system icons, which on this Mac is left of Control Center and the clock, not between them.
- The ON/OFF were in Settings' first row, not on the blob; the corner X now quits. A released number is never reused; this one built green first time.

## v34 (16.11.2026)
- The install quit is refused during a take: the old copy was replaced on disk anyway before this showed; check `pgrep` after the quit and wait (loop the quit until the take is over) before relaunching. Never kill it.
- A reachable() that holds its lock during the 4 s health call makes every take wait behind the 20 s background check; the lock now covers only the shared fields.
- A full-screen app hides the menu bar: the strip screenshot is black; look when no full-screen app is on the MacBook screen.

## v35 (16.11.2026)
- A pause for N takes was the wrong cure; the cure is the macro that brings Tailscale up, started by the miss itself and never waited for by a take.
- `$0` inside a closure that also has an explicit `k in` argument does not compile; name the outer argument too.
- Menu-bar line seen 16.11.2026 (shots/menubar-v35.png): "GROQ EN · 0.9 s" with the meter underline, nothing else.

## v36 (16.11.2026)
- A control hidden in the mode its owner actually uses is a control that does not exist for him: when a mode is added, every control gets a place in it, and the screenshot of THAT mode is the proof.
- The status item can hold the grip as a subview next to the display view; the item must keep its own length (display words + grip) and the layout timer must stop once the display has left.

## v37 (16.11.2026)
- A menu-bar app: the status item is the app; windows hide with their own ✕, only the item's menu quits. Keep the item alive (isVisible KVO) because macOS lets the user drag it out of the bar.
- Dropping the display from the blob = LINE_H 0 and not adding the view to the face; the old placeLine code stays harmless.
- Grips: three thin mid-grey lines; bright pairs look like a pause button.

## v38 (16.11.2026)
- The menu items stay in sync by reading the settings when the menu opens, and every pick calls the same refresh as the blob's buttons. The Show/Hide item is found by its action, not by position.
- A status-item menu can be photographed without the mouse: a notification that performClick()s the button and cancelTracking() on a timer.

## Lesson: hover card and pipes (16.11.2026)
Poll the mouse (macOS draws a status item once per display, only one copy owns the button, so a tracking area misses the other display). The panel needs `titleVisibility = .hidden` for the one-title guard. A non-activating NSPanel at statusBar+1 never takes focus. Pipes for text items: attributed title; for icon items: pipedIcon + rightPipe; for view items: drawPipes or PipesView.

## v39 (17.11.2026)
- `var a = false, b = false { didSet }` fails to compile again (the third time): one `var` per observed property.
- A rename keeps what lives on disk: the data folder, the log, the bundle id and the API are not the app's visible name. The self-updater matches the new .app by the OLD bundle name, so the rename version itself is installed by hand.
- One selection, two doors: the pill's dropdown and Settings both call `HearEngine.setEngine`; a test hook that sets the same default proves the path without a click.
- A popUp menu from a non-activating panel keeps the target app's focus; `menu.cancelTracking()` on a .common-mode timer lets a test photograph it.
- The pill sits on the MacBook screen (x 3200 here); check the window list before a shot.

## v40-v41 (17.11.2026)
- "The menu item" / "the drop down menu for the menu item" in Marko's words = the MENU BAR ITEM's dropdown (the status item's menu), not the pill. v39 built the wrong thing and called it done: when a UI word is ambiguous, check it against the screen he uses (menu bar) before building.
- Proof for a menu: AXPress the status item (System Events, menu bar 1), AXPress the submenu item, list `name of every menu item`, screencapture the screen the menu opened on (it can be the other display). Separators count as items when addressing by index.
- A submenu is rebuilt in the parent's menuNeedsUpdate, from one shared builder (Stripe.engineItems), so the pill and the menu bar cannot drift.
- The blob did not come back at start because autoHide minimized it 2.5 s after launch: look for the timer, not for a saved state.
- An AX press on a wrong index changes real settings (it set AUTO and opened Settings): restore the defaults afterwards.

## v42-v43 (17.11.2026)
- Per-language preferences: put the language into the key (`<name>_<lang>`) inside the one getter/setter every reader already uses, and migrate once before the first window exists; nothing else has to change.
- DICTATION ONLY INSERTS. An Accessibility insert can leave the inserted text selected (Firefox); the next insert then replaces it. Collapse the selection before and after, verify prefix and suffix, undo on a mismatch. Rule: MANTRA_MANIFEST modules/dictation-insert-only.md.
- A test of a typing path needs two takes in a row into a real box; a single take hides this bug. Simulate the app's quirk (select the first take through AX) when the real app cannot be used.
- Test boxes steal the target (the last box focused): give his box the focus back (iTerm2 activate) and close the test documents.

## v44-v45 (17.11.2026)
- A test that appends takes must read the box back each time: two takes in a row gave "minutes.Second" until the separator rule (space unless start, newline, opener) went into the one insert function.
- A status item with a menu opens it on every click; to intercept a click, take the menu away (it.menu = nil) and use the button's target/action for as long as the state lasts, then give it back.
- My TextEdit tests take the typing target: once his own dictation landed in the test box. Run them only when no take is near.


## v63 (22.11.2026): the centre oval removed
- Round 1: 7 of 10 (looks unseen, pin weak, docs). Round 2 (v64) changed: hook `state`/`screen` so paused and transcribing are seen on both screens; the pin keeps an explicit list of files allowed to create a window; TAKEOVER top states the current version. Lesson: a state you cannot trigger is a state nobody has seen; give every look a hook before calling it done, and a pin must list what is allowed, not only grep what is forbidden.
- Marko: "recording blob can go away. Something which is happening in the middle of the screen needs to go away." TakeHUD.swift and its three calls (start, two refresh) deleted, not hidden. Before deleting a status window, list what it shows and where each state lives after: the pill is closed by default since v61, so Paused and Transcribing would have been visible nowhere; the ellipse carries them now. CI script .github/ci/no_centre_status.sh pins it.

## v62 (21.11.2026): the bottom ellipse
- The spectrum reuses MicBands' sample ring (feed from captureOutput); the hook needs its own temporary AVCaptureSession because MicBands only runs while a take records. Screenshot test: `say` through the speakers into the microphone, `screencapture -R` on the bottom centre of the screen with the mouse (the primary screen is the BenQ, 1440x2560, bottom = y 2560 in screencapture coordinates). The indicator goes to the screen with the mouse pointer.
