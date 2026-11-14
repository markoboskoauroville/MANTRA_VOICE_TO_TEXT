# Lessons

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
