# Voice to Text (Mantra)

Until v1 "Mantra Voice to Text" (renamed 1.11.2026 at Marko's word, v2). Website https://mantravoicetotext.pages.dev, files on the public release markoboskoauroville/mantra-voice-to-text-downloads.

Press F1, talk, press F1 again: your words are typed wherever the cursor is. Whisper Turbo runs on your own computer
(offline, nothing leaves the machine); an optional Anthropic key adds Auto correct and the STYLE button.

**v3 (1.11.2026): one app.** Marko: *"Please unite these two apps. So public one is also my local one and everything is
developed under one hood."* Transcribe Voice to Text RT (repo MARKO_TRANSCRIBE, now only a pointer here) and this public
app are one: /Applications/Voice to Text (Mantra).app on his Mac is the same build as the download. His extras are in
`mac/Sources/Local.swift` and turn on only where they find his setup: the MANTRA_VOICE ears on :8837 (⚙ choice, default
when ~/Developer/MANTRA_VOICE exists), Speechify's start/stop sounds when Speechify is installed, his names and
corrections (⚙ Names, `corrections.txt`), the key-file picker beside the paste field. His settings, keys and history moved
over once (`Merge.once`). Every build installs into /Applications and swaps the running copy; the star row points here.

**VT in the menu bar (v5, Mac):** grey at rest, red while a take records, yellow while it is written down and corrected,
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
