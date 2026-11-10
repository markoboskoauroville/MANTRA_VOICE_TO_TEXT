---
name: voice-to-text
description: Voice to Text (Mantra), Marko's Mac dictation app (repo MANTRA_VOICE_TO_TEXT): F1 talk, text typed at the cursor; since v13 the same 13 transcription engines as TTT, numbered key rings, key import by shape, engine panel, History re-transcribe. Use for ANY Voice to Text (Mantra) / Mac dictation app / its engines / its keys task.
---
# Voice to Text (Mantra): TTT's engines on the Mac

Marko, 10.11.2026: "upgrade my local app, my voice-to-text app, to have the same features as my TTT app for voice transcription with all these models and everything. Same copy."

## SPACE (where it happens)
- The Mac. Repo ~/Developer/MANTRA_VOICE_TO_TEXT (markoboskoauroville), Swift in mac/Sources, app /Applications/Voice to Text (Mantra).app, bundle com.mantra.voicetotext, log ~/Library/Logs/voice-to-text-mantra.log, data ~/Library/Application Support/Voice to Text (Mantra) (keys.json 0600, ring.json, history/).
- Compiled only by GitHub Actions (workflow build.yml, release vN Latest); the Mac downloads, signs "Mantra Apps", quits the old copy by AX, opens the new one. Never swiftc here.
- Key notes: ~/Downloads/API (only files named groq, deepgram, assembly, speechmatics, soniox, eleven, gemini, google-stt, cloudflare-workers, claude, anthropic, haiku are read).
- Twin: TTT_MINI (the Android keyboard, another owner) and the CLI scribe (MAC_TRANSCRIBER).

## CHARACTERS (who acts)
| Character | Who | Can | Must not |
|---|---|---|---|
| The pill | F1 stripe, EN / HR / AUTO | record, show engine, key number, status | take focus |
| The 13 engines | Catalog.swift: Parakeet, Whisper Turbo (this Mac), Groq turbo, Groq large-v3, Cloudflare, Gemini, Deepgram, AssemblyAI, Speechmatics, Google v1, Chirp 3, Soniox, ElevenLabs | write the take down | run paid ones unless picked (Soniox, ElevenLabs) |
| Groq 1/3, Groq 2/3 ... | the numbered keys of a ring (Ring in Keys.swift) | rotate always on, wrap to key 1, rest until 00:00 UTC / a minute / an hour | be shown, logged, committed |
| KeyImporter | the picker and the by-itself import | sort keys by shape, test each free, keep the working | read other secrets in ~/Downloads/API |
| Chain | retry only | wait 3 s and retry the same engine on a network error, up to 10 times | change engine by itself (never, v14) |
| History | the second tab | Re-transcribe with any engine and language, accuracy % beside each | |
| Marko | tester | the voice test, the hands | |

## PLOT
**Trigger:** change or test an engine, a key, the panel, the fallback.
1. Read TAKEOVER.md and LESSONS.md; save the request word for word in momentaryupdates.md and push first.
2. Change Sources; push main; read the run (gh run list / view --log-failed); the colour is the check.
3. Install the release: gh release download, unzip to /Applications, sign "Mantra Apps" + com.mantra.voicetotext, quit the old copy by AX (distributed notification com.mantra.voicetotext.quit, refused during a take), open the new one.
4. Tests without Marko's voice: `"<app>/Contents/MacOS/Voice to Text (Mantra)" --hear <engine id> <file> [en|hr|auto] [--only]`; `--keys`, `--parse <file>`, `--import-keys <file>`, `--retest-keys`. Spoken test files by `say` (Samantha, Lana).
   **Turning point (rotation):** `defaults write com.mantra.voicetotext testDropKeys -int 1` makes key 1 of every job fail, the answer says "Groq 1/3 no connection -> Groq 2/3"; delete the default afterwards.
   **Turning point (Croatian):** auto correct is off for Croatian takes (Prefs.correctCroatian, TTT's maAiCorrectDictation); the STYLE button is not touched.
5. A test needing his voice: one message to the master.
**Ending:** the release link and run colour, what was proven and what not.

## RULES
- Free calls only for key tests (list or auth calls); a paid transcription needs `spend ask`. Soniox and ElevenLabs only when picked.
- No key printed. Names: Groq (never Grok), Deepgram, AssemblyAI, Speechmatics, Gemini; "(Mantra)" last. Whole-number versions.
- Accuracy percentages shipped are TTT's benchmark of 9.11.2026 (circular for Groq large-v3); a measured one replaces them.

## HISTORY
- 10.11.2026, v14: no automatic engine change; retry 3 s x 10 on network errors; testNetFail default for the test.
- 10.11.2026, v13: the thirteen engines, numbered rings, import by shape, engine panel, Croatian correction off, History picker with accuracy. Android on-device became Whisper on this Mac.

- **Pressable controls highlight** on hover/press, nothing else does: MANTRA_MANIFEST modules/workflow-interface.md, "Pressable controls highlight" (Marko 10.11.2026).
