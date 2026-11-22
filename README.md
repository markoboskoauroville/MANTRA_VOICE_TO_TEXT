# Vox to Txt (Mantra)

Until v38 "Voice to Text (Mantra)" (renamed 17.11.2026, v39, at Marko's word: "Vox to Txt"). Bundle id, data folder (Application Support/Voice to Text (Mantra)), log, :8865 API and the GitHub repo are unchanged.

Until v1 "Mantra Voice to Text" (renamed 1.11.2026 at Marko's word, v2). Website https://mantravoicetotext.pages.dev, files on the public release markoboskoauroville/mantra-voice-to-text-downloads.

**v69 (22.11.2026):** the Frankfurt relay is only observed: one notice when it goes down and one when it is back, a growing pause while it is down, no Tailscale repair.

**v66 (22.11.2026):** the STYLE button always styles the text box you are in: Claude Opus first, Groq second; the pill says who styled it, and the button becomes UNDO for 30 seconds.

**v65 (22.11.2026):** the ellipse is on the screen of the text cursor (insertion point, else focused element, else focused window, the mouse only last) and follows it to the other screen.

**v64 (22.11.2026):** test hook for the ellipse takes `state` (recording, paused, transcribing) and `screen`; the CI pin lists every file allowed to create a window.

**v63 (22.11.2026):** the oval in the middle of the screen (TakeHUD) is gone; the bottom ellipse with the spectrum is the only recording indicator, and it also stays up (bars frozen and dim) while paused and (quiet moving wave) while the take is written down.

**v62 (21.11.2026):** a small ellipse with a 20-bar live spectrum shows at the bottom of the screen while a take records (RecordingIndicator.swift).

Press F1, talk, press F1 again: your words are typed wherever the cursor is. Whisper Turbo runs on your own computer
(offline, nothing leaves the machine); an optional Anthropic key adds Auto correct and the STYLE button.

**v3 (1.11.2026): one app.** Marko: *"Please unite these two apps. So public one is also my local one and everything is
developed under one hood."* Transcribe Voice to Text RT (repo MARKO_TRANSCRIBE, now only a pointer here) and this public
app are one: /Applications/Vox to Txt (Mantra).app on his Mac is the same build as the download. His extras are in
`mac/Sources/Local.swift` and turn on only where they find his setup: the MANTRA_VOICE ears on :8837 (⚙ choice, default
when ~/Developer/MANTRA_VOICE exists), Speechify's start/stop sounds when Speechify is installed, his names and
corrections (⚙ Names, `corrections.txt`), the key-file picker beside the paste field. His settings, keys and history moved
over once (`Merge.once`). Every build installs into /Applications and swaps the running copy; the star row points here.

**VT in the menu bar (v5, Mac):** grey at rest, a red stopwatch with the take's time (m:ss) while it records (v6; grey and still while paused), yellow while it is written down and corrected,
grey again once pasted; a click opens Show the blob, Settings, History, Quit (`mac/Sources/MenuBar.swift`).

**The duck (v3, Mac and Windows):** *"reduce audio output while it's listening to the microphone to 6%. When listening is
done, it brings it back to old value."* While a take records (not paused) the default output is at 6 %; stop, pause, ✕,
Esc, quit put back the level it had, and a crash is put right at the next start. ⚙ "Speakers at 6 % while listening".
Test: `--duck-test` (Mac prints, Windows logs).

| Folder | What |
|---|---|
| `mac/` | the Mac app (Swift, whisper.cpp with Metal inside) |
| `windows/` | the Windows app (C# .NET, Whisper.net) |
| `site/` | the website (Cloudflare Pages) |

Documents: [TAKEOVER.md](TAKEOVER.md), [LESSONS.md](LESSONS.md), [momentaryupdates.md](momentaryupdates.md).
