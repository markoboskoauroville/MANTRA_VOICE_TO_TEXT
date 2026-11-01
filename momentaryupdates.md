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
