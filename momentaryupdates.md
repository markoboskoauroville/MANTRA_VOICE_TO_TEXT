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
