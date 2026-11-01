# Takeover

Started 1.11.2026.

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
