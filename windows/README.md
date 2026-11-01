# Mantra Voice to Text for Windows (v1)

A small floating blob that hears you, writes down what you said on your own PC (Whisper, offline), cleans it with
Claude if you want, and types it where your cursor is. The Windows copy of the Mac app (`../mac`, first built as
MARKO_TRANSCRIBE), without the Mac-only parts (voice activation, Accessibility, Speechify).

## Use

1. Unzip `MantraVoiceToText-v1-win-x64.zip` (Intel / AMD PCs) or `MantraVoiceToText-v1-win-arm64.zip` (Snapdragon,
   Windows on a Mac) anywhere and start `MantraVoiceToText.exe`. Nothing is installed; the settings live in
   `%LOCALAPPDATA%\Mantra Voice to Text`.
2. ⚙ → Settings → **Download the model (547 MB)** (Whisper large-v3-turbo q5_0 from Hugging Face, once). The download
   **always resumes**: it goes to `…\models\ggml-large-v3-turbo-q5_0.bin.part` with an HTTP Range from the .part's size,
   a dropped connection is tried again by itself (2, 4, 8 … 60 s apart), and when the app is closed and opened again it
   goes on by itself from where it stopped (no button). At exactly 574,041,195 bytes it becomes the .bin. If you already
   have `ggml-large-v3-turbo-q5_0.bin`, put it in `%LOCALAPPDATA%\Mantra Voice to Text\models` instead.
   Whisper needs the **Microsoft Visual C++ runtime** (2015-2022); most PCs have it. When it is missing the blob says so
   and ⚙ → Settings has a **Get it** button (Microsoft's vc_redist for x64 or arm64).
3. Optional: paste your Anthropic key into ⚙ → Settings → Anthropic key → Save (Test lists your models, nothing billed).
   Without a key the words are typed as heard and the line says "Auto correct needs an Anthropic key in ⚙".
4. Click into any text box, press **F1**, talk, press **F1** again. **Esc** while recording throws the take away.

The blob: ✕ (throw the take away, or hide the blob), [AUTO]/[EN]/[HR] (Whisper's language), the voice in eleven bars,
⏸ pause, COPY, STYLE, ⚙ and the blue button (mic: start; arrow: send). COPY and STYLE are grey at rest; STYLE is white
while an Auto correct model is chosen; COPY is white while the last take landed in no text box and waits for COPY; both
are green while they work. Drag the blob by any part that is not a button; a short click on the status line moves it
below the pill or back above. The blob never takes the keyboard focus. The tray icon brings it back (left click) and
has Settings and Quit.

**STYLE:** click into any text box (or select part of its text), then STYLE: the selection, or the whole box, is
rewritten by the Claude model chosen in ⚙ → The STYLE button and written back in place (UI Automation; a selection is
pasted over). When it cannot be written back it goes on the clipboard and the line says "press Ctrl+V".

**Typing** is clipboard + Ctrl+V (SendInput); the clipboard's text (plain, RTF, HTML) is put back 0.4 s later
(a picture or files on the clipboard are not kept). Terminals (Windows Terminal, the console) count as text boxes. When the focused
element is not a text box (UI Automation: not an Edit or Document, no editable value, no caret) the take did not land:
the blob stays, the line says so in amber, COPY is white.

**Silence gate:** a take under 0.5 s or quieter than -45 dBFS peak is "nothing said: not sent" (Whisper invents words
for silence). Whisper's own inventions for silence ("Thank you", "[BLANK_AUDIO]") are dropped too.

## Build

The .NET 8 SDK (8.0.427) on Windows. In the Parallels VM it is in `C:\dotnet`; the script copies the sources to
`C:\mvt` (fast local disk), builds, publishes self-contained single files and zips them into `dist\`:

```
powershell -ExecutionPolicy Bypass -File windows\build.ps1             # build only
powershell -ExecutionPolicy Bypass -File windows\build.ps1 -Publish    # + dist\MantraVoiceToText-v1-win-x64.zip, -win-arm64.zip
```

From the Mac: `prlctl exec "Windows 11" --current-user powershell -ExecutionPolicy Bypass -File 'Y:\Developer\MANTRA_VOICE_TO_TEXT\windows\build.ps1' -Publish`
(Y: is the Mac home shared by Parallels). The NuGet cache is `windows\build\nuget` (gitignored), so nothing is
downloaded twice.

Packages: Whisper.net 1.9.1 + Whisper.net.Runtime 1.9.1 + Whisper.net.Runtime.NoAvx 1.9.1 (whisper.cpp, CPU; NoAvx for
old x64 CPUs and x64 emulation on ARM), NAudio.Core / NAudio.WinMM 2.2.1, Anthropic 13.3.0 (the official C# SDK). WPF,
with WinForms only for the tray icon. The single-file exe extracts itself once to `%TEMP%\.net\MantraVoiceToText`
(`IncludeAllContentForSelfExtract`, so Whisper.net finds its DLLs).

| File | What |
|---|---|
| `src/Program.cs` | start, single instance, tray icon, test switches, `--pill-shot` |
| `src/Stripe.cs` | the blob's behaviour: take, gate, Whisper, Auto correct, typing, COPY, STYLE, ⚙ menu |
| `src/Pill.cs` | the pill's look: buttons, voice meter, status line, the no-focus topmost window, dragging |
| `src/Audio.cs` | microphone at 16 kHz mono, peak, the eleven-band FFT meter, WAV reading |
| `src/ModelDownload.cs` | the model download that always resumes (.part, Range, retries, goes on at every start) |
| `src/Ears.cs` | Whisper.net: model loaded once (warmed when a take starts), language auto / en / hr |
| `src/Claude.cs` | the correction rules (from the Mac app), model by family from the Models API, Messages call |
| `src/Hands.cs` | focus check (UI Automation), clipboard + Ctrl+V, STYLE read / write back, global hotkey |
| `src/SettingsWindow.cs` | ⚙ Settings: ON · OFF · name · TOP · ✕, microphone, hotkey, key, model download, After hide, history |
| `src/Prefs.cs` | settings.json, the key (DPAPI), history.json, log.txt |

## Test switches

```
MantraVoiceToText.exe --pill-shot <dir>              the blob's faces as PNGs (ready, recording, writing, not landed,
                                                     styling, no auto correct, copied, no key, line below); nothing on screen
MantraVoiceToText.exe --take <file.wav> [--no-type] [--exit]
                                                     a recording through the same road as a microphone take;
                                                     --no-type writes it down only, --exit quits 4 s after
MantraVoiceToText.exe --press <id> [s]               presses a blob button after s seconds exactly as a click does
                                                     (close, language, pause, copy, style, settings, send)
MantraVoiceToText.exe --repeat <n>                   with --take: the same file n times (cold, then warm)
MantraVoiceToText.exe --bands <file.wav>             the voice meter's eleven bands every 0.1 s, into the log
MantraVoiceToText.exe --download-model               starts the model download (a waiting .part goes on by itself anyway)
MantraVoiceToText.exe --settings-shot <png>          ⚙ Settings drawn into a PNG, then exit
MantraVoiceToText.exe --settings                     opens ⚙ Settings at the start
MantraVoiceToText.exe --test-style-fake              STYLE writes the box back in CAPITALS without Claude
                                                     (tests the reading and writing back of the focused box)
```

Results go to `%LOCALAPPDATA%\Mantra Voice to Text\log.txt` (what was heard, the times, where it landed; never the key).
Test recordings: `test/en-test.wav` (macOS `say`, Samantha, 16 kHz), `test/hr-test.wav` (`say`, Lana, Croatian) and
`test/silence.wav` (2 s of digital silence). Pictures of the blob and Settings from the tests: `docs/`.

## Testing in the Parallels VM from the Mac

`tools/vmx.sh <script.ps1> [args]` resumes the VM if it suspended itself and runs a script as the user. The scripts
(all run inside Windows, the Mac's home is `Y:`): `run.ps1` (start with switches, wait, print the new log lines),
`start.ps1`, `notepad.ps1` (a take typed into a fresh Notepad, read back by UI Automation), `nolanding.ps1` (a take with
the desktop focused, then COPY), `styletest.ps1 [-Select]` (STYLE on Notepad with `--test-style-fake`), `keys.ps1` (F1,
Esc, the ⚙ menu, the focus kept), `dltest.ps1` (start the download, kill, start again: it resumes; the real model is put
back), `reltest.ps1 -Rid win-x64|win-arm64` (the zip unzipped and run), `liveshot.ps1` (Win+PrtScn copied out: GDI
screenshots miss the blob, LESSONS.md), `press.ps1` (a button through UI Automation; it moves the focus).
