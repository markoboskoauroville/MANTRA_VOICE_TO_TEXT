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
