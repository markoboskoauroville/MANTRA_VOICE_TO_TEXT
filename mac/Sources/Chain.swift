// THE CHAIN (ported from TTT's FallbackRunner / EngineChain, 10.11.2026): the engine picked for the language goes first; when
// every key of it fails (the ring has already tried them all, wrapping to key 1), the walk goes on through TTT's order for
// that language: free engines only, with a key, with free quota left in their window; paid ones (Soniox, ElevenLabs) only
// when picked. Whisper Turbo on this Mac is the last of the free ones. The status line says every step.
import Foundation

enum Chain {
    static func run(_ h: HearEngine, source: URL) -> Result<String, EngineError> {
        guard let pcm = Audio.pcm16k(source), pcm.count > 8000 else { return .failure(EngineError("nothing recorded")) }
        let seconds = Double(pcm.count) / 16000
        let wav = Ears.wav16(pcm)
        var ids = [h.id]
        for id in Catalog.order(h.lang) where !ids.contains(id) { ids.append(id) }
        var steps: [String] = [], lastError = "no engine could run"
        for id in ids {
            guard let spec = Catalog.byId(id) else { continue }
            let picked = id == h.id
            if !picked {
                if spec.paid || !Catalog.available(spec) || !Quota.canAfford(spec, seconds: seconds) { continue }
            }
            let t0 = Date()
            let r = once(spec, source: source, wav: wav, lang: h.lang, seconds: seconds)
            switch r {
            case .success(let text):
                Quota.add(spec, seconds: seconds)
                Hear.used = spec.short + " " + h.lang.uppercased()
                appendLog(String(format: "engine %@ (%@) %.1f s", spec.id, h.lang, Date().timeIntervalSince(t0)))
                if !steps.isEmpty {
                    let said = steps.joined(separator: " → ") + " → \(spec.short)"
                    Ring.lastMove = [Ring.lastMove, said].compactMap { $0 }.joined(separator: "; ")
                }
                return .success(text)
            case .failure(let e):
                lastError = e.message
                appendLog("engine \(spec.id) failed: \(e.message)")
                if e.message == "nothing recorded" { return r }
                steps.append("\(spec.short) failed")
            }
        }
        return .failure(EngineError("every engine failed, the last: " + lastError))
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
