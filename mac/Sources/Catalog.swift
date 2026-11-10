// THE 13 ENGINES (v13, Marko, 10.11.2026: "upgrade my local app, my voice-to-text app, to have the same features as my TTT
// app for voice transcription with all these models and everything. Same copy."). Ported from TTT's EngineLogic.kt /
// EngineScores.kt (builds 577-596): the same thirteen, the same free quotas, the same orders, the same accuracy figures.
// The one difference is the phone's own: "Android on-device" has no Mac twin, so the thirteenth is Whisper Turbo on this
// Mac (the app's own whisper.cpp). Parakeet is the MANTRA_VOICE ears' model, offered only where those ears live.
import Foundation

enum Reset: String { case hourly, daily, monthly, oneOff, none }

struct EngineSpec {
    let id: String
    let name: String
    let short: String
    let ring: Provider?                  // nil: runs on this Mac
    let freeSeconds: Double              // free audio per reset period
    let reset: Reset
    let pricePerHour: Double
    let paid: Bool                       // no free quota known: runs only when picked

    var local: Bool { ring == nil }
    var freeMinutes: Int { freeSeconds.isFinite ? Int((freeSeconds / 60).rounded()) : 0 }

    /// the label under the name: free or paid, and the minutes (TTT: "free · 480 min/day")
    var label: String {
        if local { return "free · offline, no limit" }
        if paid { return String(format: "paid · $%.2f/h, only when picked", pricePerHour) }
        let n = Catalog.thousands(freeMinutes)
        switch reset {
        case .daily: return "free · \(n) min/day"
        case .monthly: return "free · \(n) min/month"
        case .hourly: return "free · \(n) min/hour"
        case .oneOff: return "free credit · \(n) min, once"
        case .none: return "free"
        }
    }
}

enum Catalog {
    static let all: [EngineSpec] = [
        EngineSpec(id: "parakeet", name: "Parakeet (this Mac, fast)", short: "Parakeet", ring: nil, freeSeconds: .infinity, reset: .none, pricePerHour: 0, paid: false),
        EngineSpec(id: "whisper", name: "Whisper Turbo (this Mac, offline)", short: "Whisper", ring: nil, freeSeconds: .infinity, reset: .none, pricePerHour: 0, paid: false),
        EngineSpec(id: "groq_turbo", name: "Groq Whisper turbo", short: "Groq turbo", ring: .groq, freeSeconds: 28_800, reset: .daily, pricePerHour: 0.04, paid: false),
        EngineSpec(id: "groq_v3", name: "Groq Whisper large-v3", short: "Groq", ring: .groq, freeSeconds: 28_800, reset: .daily, pricePerHour: 0.111, paid: false),
        EngineSpec(id: "cloudflare", name: "Cloudflare Workers AI Whisper", short: "Cloudflare", ring: .cloudflare, freeSeconds: 12_840, reset: .daily, pricePerHour: 0.03, paid: false),
        EngineSpec(id: "gemini", name: "Gemini Flash-Lite audio", short: "Gemini", ring: .gemini, freeSeconds: 3_600, reset: .daily, pricePerHour: 0.04, paid: false),
        EngineSpec(id: "deepgram", name: "Deepgram Nova-3", short: "Deepgram", ring: .deepgram, freeSeconds: 2_300_000, reset: .oneOff, pricePerHour: 0.31, paid: false),
        EngineSpec(id: "assemblyai", name: "AssemblyAI", short: "AssemblyAI", ring: .assemblyai, freeSeconds: 1_200_000, reset: .oneOff, pricePerHour: 0.15, paid: false),
        EngineSpec(id: "speechmatics", name: "Speechmatics", short: "Speechmatics", ring: .speechmatics, freeSeconds: 1_500_000, reset: .oneOff, pricePerHour: 0.24, paid: false),
        EngineSpec(id: "google_v1", name: "Google Speech v1", short: "Google", ring: .google, freeSeconds: 3_600, reset: .monthly, pricePerHour: 1.44, paid: false),
        EngineSpec(id: "google_chirp", name: "Google Chirp 3 (v2)", short: "Chirp 3", ring: .chirp, freeSeconds: 3_600, reset: .monthly, pricePerHour: 0.96, paid: false),
        EngineSpec(id: "soniox", name: "Soniox", short: "Soniox", ring: .soniox, freeSeconds: 0, reset: .none, pricePerHour: 0.10, paid: true),
        EngineSpec(id: "elevenlabs", name: "ElevenLabs Scribe", short: "ElevenLabs", ring: .elevenlabs, freeSeconds: 0, reset: .none, pricePerHour: 0.22, paid: true),
    ]

    static func byId(_ id: String) -> EngineSpec? { all.first { $0.id == id } }

    static func thousands(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","; f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // TTT's recommended chains (docs/stt-providers.md), the rest after, so every engine has a place
    static let orderEN = ["parakeet", "groq_turbo", "cloudflare", "deepgram", "assemblyai", "gemini", "speechmatics", "groq_v3", "whisper", "google_chirp", "google_v1", "soniox", "elevenlabs"]
    static let orderHR = ["groq_v3", "elevenlabs", "deepgram", "parakeet", "cloudflare", "gemini", "assemblyai", "speechmatics", "groq_turbo", "whisper", "google_chirp", "google_v1", "soniox"]
    static func order(_ lang: String) -> [String] { lang == "en" ? orderEN : orderHR }

    /// can this engine run now: a local one where it lives, a cloud one with at least one working key
    static func available(_ s: EngineSpec) -> Bool {
        if let p = s.ring { return !Keys.entries(p).isEmpty }
        if s.id == "parakeet" { return Ears.serverHere }
        return Ears.current == .server || Model.ready
    }

    static func shown(_ s: EngineSpec, lang: String) -> String { s.name + Scores.suffix(s.id, lang) }
}

// MARK: the accuracy next to each engine (TTT EngineScores: "100% is the best, less is worse"), per language
// The shipped figures are TTT's benchmark of 9.11.2026 (docs/benchmark-2026-11-09.md in TTT: the last 5 Croatian and 5
// English real dictations; Groq large-v3 is circular there, it made most of the references). A score measured on this Mac
// replaces the shipped one (Scores.record).

enum Scores {
    static let shipped: [String: [String: Int]] = [
        "hr": ["groq_v3": 100, "google_chirp": 98, "assemblyai": 96, "deepgram": 94, "cloudflare": 90, "speechmatics": 90,
               "groq_turbo": 90, "gemini": 88, "google_v1": 86, "parakeet": 78],
        "en": ["groq_v3": 99, "google_chirp": 89, "assemblyai": 91, "deepgram": 87, "cloudflare": 88, "speechmatics": 85,
               "groq_turbo": 89, "gemini": 90, "google_v1": 82, "parakeet": 85],
    ]

    static func stored() -> [String: [String: Int]] {
        (UserDefaults.standard.data(forKey: "engineScores")).flatMap { try? JSONDecoder().decode([String: [String: Int]].self, from: $0) } ?? [:]
    }
    static func get(_ id: String, _ lang: String) -> Int? {
        let l = lang == "en" ? "en" : "hr"
        return stored()[l]?[id] ?? shipped[l]?[id]
    }
    static func record(_ id: String, _ lang: String, pct: Int) {
        var s = stored(); let l = lang == "en" ? "en" : "hr"
        var d = s[l] ?? [:]; d[id] = pct; s[l] = d
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "engineScores") }
    }
    /// " (96%)" or ""
    static func suffix(_ id: String, _ lang: String) -> String { get(id, lang).map { " (\($0)%)" } ?? "" }

    // word error rate, as TTT's Wer: lower-case, no punctuation, accents kept
    static func words(_ t: String) -> [String] {
        t.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    static func accuracy(reference: String, heard: String) -> Int {
        let r = words(reference), h = words(heard)
        guard !r.isEmpty else { return h.isEmpty ? 100 : 0 }
        var prev = Array(0...h.count)
        for i in 1...r.count {
            var cur = [i] + [Int](repeating: 0, count: h.count)
            if !h.isEmpty { for j in 1...h.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1)) } }
            prev = cur
        }
        let wer = Double(prev[h.count]) / Double(r.count)
        return max(0, min(100, Int(((1 - wer) * 100).rounded())))
    }
}

// MARK: the free quota, counted here (TTT Quota): seconds of audio sent to each free engine in its window; an engine whose
// free window is used up is skipped by the fallback walk (the one picked is always tried: the key ring and the provider decide)

enum Quota {
    static func windowStart(_ r: Reset, _ now: Date = Date()) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        switch r {
        case .hourly: return c.dateInterval(of: .hour, for: now)?.start ?? now
        case .daily: return c.startOfDay(for: now)
        case .monthly: return c.dateInterval(of: .month, for: now)?.start ?? now
        default: return Date(timeIntervalSince1970: 0)
        }
    }

    static func used(_ s: EngineSpec, _ now: Date = Date()) -> Double {
        guard let d = UserDefaults.standard.dictionary(forKey: "quotaUsed")?[s.id] as? [String: Double] else { return 0 }
        if s.reset == .oneOff { return d["seconds"] ?? 0 }
        return (d["start"] ?? 0) >= windowStart(s.reset, now).timeIntervalSince1970 ? (d["seconds"] ?? 0) : 0
    }

    static func add(_ s: EngineSpec, seconds: Double, _ now: Date = Date()) {
        guard !s.local, !s.paid else { return }
        var all = UserDefaults.standard.dictionary(forKey: "quotaUsed") ?? [:]
        let was = used(s, now)
        all[s.id] = ["start": windowStart(s.reset, now).timeIntervalSince1970, "seconds": was + seconds]
        UserDefaults.standard.set(all, forKey: "quotaUsed")
    }

    static func canAfford(_ s: EngineSpec, seconds: Double) -> Bool {
        if s.local { return true }
        if s.paid { return false }
        return used(s) + seconds <= s.freeSeconds
    }
}

// MARK: who hears: an engine of the catalogue and a language (the pill's EN / HR / AUTO)
// Each language keeps its own engine, as TTT's H key (Croatian) and E key (English) do (sel_hr / sel_en).

struct HearEngine: Equatable {
    var id: String
    var lang: String

    var spec: EngineSpec { Catalog.byId(id) ?? Catalog.all[1] }
    var title: String { "\(spec.short) \(lang.uppercased())" }
    var isParakeet: Bool { id == "parakeet" }
    var isAssembly: Bool { id == "assemblyai" }

    static func fresh(_ id: String, _ lang: String) -> HearEngine { HearEngine(id: id, lang: lang) }

    /// what this Mac can offer in the pickers: every engine of the catalogue
    static var offered: [EngineSpec] { Catalog.all }

    static var langs = ["en", "hr", "auto"]

    static var current: HearEngine {
        get {
            let d = UserDefaults.standard
            // v13, once: the choice of v12 and before ("assemblyAuto", "whisperHR", ...) becomes an engine and a language
            if !d.bool(forKey: "v13engines") {
                d.set(true, forKey: "v13engines")
                let was = d.string(forKey: "hear") ?? "assemblyAuto"
                let lower = was.lowercased()
                let lang = lower.hasSuffix("en") ? "en" : lower.hasSuffix("hr") ? "hr" : "auto"
                let id = lower.hasPrefix("parakeet") ? "parakeet" : lower.hasPrefix("whisper") ? "whisper" : "assemblyai"
                d.set(lang, forKey: "hearLang")
                for l in langs { d.set(id, forKey: "engine_" + l) }
            }
            let lang = d.string(forKey: "hearLang") ?? "auto"
            var id = d.string(forKey: "engine_" + lang) ?? "assemblyai"
            if Catalog.byId(id) == nil || (id == "parakeet" && !Ears.serverHere) { id = "assemblyai" }
            return HearEngine(id: id, lang: lang)
        }
        set {
            UserDefaults.standard.set(newValue.lang, forKey: "hearLang")
            UserDefaults.standard.set(newValue.id, forKey: "engine_" + newValue.lang)
        }
    }

    static func setEngine(_ id: String) { var h = current; h.id = id; current = h }
    static func setLang(_ lang: String) { UserDefaults.standard.set(lang, forKey: "hearLang") }
    /// EN, then HR, then AUTO, then EN again (the 🌐 button)
    static func cycleLang() { setLang(["en": "hr", "hr": "auto"][current.lang] ?? "en") }
}
