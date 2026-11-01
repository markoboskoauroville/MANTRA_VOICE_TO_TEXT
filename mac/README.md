# Voice to Text (Mantra) for Mac

```
./build.sh             # build + sign "Mantra Apps" + dist/VoiceToTextMantra-vN-mac.zip
./build.sh --install   # also into /Applications
```

Swift (the blob of MARKO_TRANSCRIBE, v29) with whisper.cpp linked in statically, Metal shaders embedded. Apple Silicon,
macOS 14+. No Python, no server, no ffmpeg: the take is recorded by AVFoundation, converted to 16 kHz by AVAudioConverter
and transcribed in the app (`Sources/Whisper.swift`). The model (`ggml-large-v3-turbo-q5_0.bin`, 574,041,195 bytes) is
downloaded from ⚙ into `~/Library/Application Support/Voice to Text (Mantra)/models`. The Anthropic key is pasted in ⚙
(`keys.json`, 0600, never shown).

**whisper.cpp:** `WHISPER=<checkout>` (default ~/Developer/VOICE_ENGINES/src/whisper.cpp, commit 482279b), with
`whisper-metal-macos15.patch` applied: macOS 15.0's runtime Metal compiler rejects `constexpr` on the bfloat casts in
`kernels/unary.metal` and the load then aborts. If a load ever aborts anyway, the next start uses the processor
(`loadingModel` / `cpuOnly` in the app's defaults).

**Tests:** `defaults write com.mantra.voicetotext testNoTyping -bool true`, then
`"build/Voice to Text (Mantra).app/Contents/MacOS/Voice to Text (Mantra)" --take file.aiff` (log:
~/Library/Logs/voice-to-text-mantra.log); `--pill-shot <dir>`, `--settings-shot <png>` draw off screen.
