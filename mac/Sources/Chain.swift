// (v14: no chain of engines any more, see run; the file name stays) THE CHAIN (ported from TTT's FallbackRunner / EngineChain, 10.11.2026): the engine picked for the language goes first; when
// every key of it fails (the ring has already tried them all, wrapping to key 1), the walk goes on through TTT's order for
// that language: free engines only, with a key, with free quota left in their window; paid ones (Soniox, ElevenLabs) only
// when picked. Whisper Turbo on this Mac is the last of the free ones. The status line says every step.
import Foundation

enum Chain {
    static func run(_ h: HearEngine, source: URL) -> Result<String, EngineError> {
        guard let pcm = Audio.pcm16k(source), pcm.count > 8000 else { return .failure(EngineError("nothing recorded")) }
        let seconds = Double(pcm.count) / 16000
        let wav = Ears.wav16(pcm)
        // v14 (Marko, 10.11.2026: "If key is exhausted, go in the next key of the same provider. Change models automatically never
        // do that."): only the engine picked runs. Its keys rotate inside Ring (same provider only); a network error or timeout
        // waits 3 s and tries the same engine again, up to 10 times, the status shown; then the take stops and stays in History.
        guard let spec = Catalog.byId(h.id) else { return .failure(EngineError("unknown engine \(h.id)")) }
        var tries = 0
        var test = UserDefaults.standard.integer(forKey: "testNetFail")     // test mode: the first N attempts fail as if offline
        while true {
            tries += 1
            let t0 = Date()
            let r: Result<String, EngineError>
            if test > 0 { test -= 1; r = .failure(EngineError("The Internet connection appears to be offline. (test)")) }
            else { r = once(spec, source: source, wav: wav, lang: h.lang, seconds: seconds) }
            switch r {
            case .success:
                Quota.add(spec, seconds: seconds)
                Hear.used = spec.short + " " + h.lang.uppercased()
                appendLog(String(format: "engine %@ (%@) %.1f s, attempt %d", spec.id, h.lang, Date().timeIntervalSince(t0), tries))
                return r
            case .failure(let e):
                appendLog("engine \(spec.id) attempt \(tries) failed: \(e.message)")
                if !isNetwork(e.message) { return r }
                if tries >= maxTries { return .failure(EngineError("\(spec.short): no answer after \(maxTries) tries, 3 s apart; the take is kept in History")) }
                let said = "\(spec.short): no connection, trying again in 3 s (\(tries) of \(maxTries))"
                Ring.lastMove = said
                onStatus?(said)
                Thread.sleep(forTimeInterval: 3)
            }
        }
    }

    static let maxTries = 10
    static var onStatus: ((String) -> Void)?
    static func isNetwork(_ m: String) -> Bool {
        let l = m.lowercased()
        return ["internet", "network", "timed out", "offline", "no answer", "could not connect", "connection", "keys tried for"].contains { l.contains($0) }
    }

    static func once(_ s: EngineSpec, source: URL, wav: Data, lang: String, seconds: Double) -> Result<String, EngineError> {
        switch s.id {
        case "parakeet": return Ears.server(source, lang: lang, model: "parakeet")
        case "whisper":
            if Ears.current == .server { return Ears.server(source, lang: lang) }
            let r = Whisper.transcribe(source, lang: lang)
            Hear.lastLang = Whisper.lastLang
            return r
        case "groq_turbo": return Adapters.groq(model: "whisper-large-v3-turbo", wav, lang: lang)
        case "groq_v3": return Adapters.groq(model: "whisper-large-v3", wav, lang: lang)
        case "cloudflare": return Adapters.cloudflare(wav, lang: lang)
        case "gemini": return Adapters.gemini(wav, lang: lang)
        case "deepgram": return Adapters.deepgram(wav, lang: lang)
        case "assemblyai": return Assembly.transcribe(wav, lang: lang)
        case "speechmatics": return Adapters.speechmatics(wav, lang: lang)
        case "google_v1": return Adapters.googleV1(wav, lang: lang, seconds: seconds)
        case "google_chirp": return Adapters.chirp(wav, lang: lang)
        case "soniox": return Adapters.soniox(wav, lang: lang)
        case "elevenlabs": return Adapters.elevenlabs(wav, lang: lang)
        default: return .failure(EngineError("unknown engine \(s.id)"))
        }
    }
}
