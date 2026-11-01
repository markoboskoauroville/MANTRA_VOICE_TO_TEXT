# Lessons

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
