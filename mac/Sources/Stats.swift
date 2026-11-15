// v24 (Marko, 15.11.2026: "Please now update how good is each engine and how fast is each engine in the engine name
// everywhere."): the engine's name carries its speed and its quality wherever it is shown: "Deepgram · 1.0 s · ★★★★☆".
// Speed: the median total time of the last 20 real takes (every dictation, every /hear call), per language.
// Quality: the mean of the last 20 scores, per language: (a) automatic, in TEST mode a take that is the reference sentence
// is compared by WER (Scores.accuracy) and (b) Marko's thumbs up (100) or down (0) per take in History; the English
// measurement of the benchmark counts as one score. Stars = score / 20, rounded, at least one. No data: "no data yet".
import Foundation

enum Stats {
    static let keep = 20
    private static let lock = NSLock()
    private static let key = "engineStats"
    /// Marko's reference sentence of 15.11.2026
    static let defaultReference = "This is a test stream recording of the concert of 17.10.2026, Češki narodni dom, Zagreb."

    // engine -> lang -> {"t": [seconds], "q": [score]}
    private static func load() -> [String: [String: [String: [Double]]]] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([String: [String: [String: [Double]]]].self, from: d) else { return [:] }
        return v
    }
    private static func save(_ s: [String: [String: [String: [Double]]]]) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func add(_ id: String, _ lang: String, _ field: String, _ value: Double) {
        lock.lock(); defer { lock.unlock() }
        var s = load()
        var byLang = s[id] ?? [:]
        var f = byLang[lang] ?? [:]
        var a = f[field] ?? []
        a.append(value)
        if a.count > keep { a.removeFirst(a.count - keep) }
        f[field] = a; byLang[lang] = f; s[id] = byLang
        save(s)
    }

    static func recordTime(_ id: String, _ lang: String, _ secs: Double) { add(id, lang, "t", secs) }
    static func recordQuality(_ id: String, _ lang: String, _ score: Int) { add(id, lang, "q", Double(score)) }
    static func rate(_ id: String, _ lang: String, up: Bool) { recordQuality(id, lang, up ? 100 : 0) }

    private static func pool(_ id: String, _ lang: String, _ field: String) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        guard let byLang = load()[id] else { return [] }
        if lang == "auto" { return Array(((byLang["en"]?[field] ?? []) + (byLang["hr"]?[field] ?? []) + (byLang["auto"]?[field] ?? [])).suffix(keep)) }
        return byLang[lang]?[field] ?? []
    }

    static func samples(_ id: String, _ lang: String) -> Int { pool(id, lang, "t").count }

    static func median(_ id: String, _ lang: String) -> Double? {
        let a = pool(id, lang, "t").sorted()
        guard !a.isEmpty else { return nil }
        let n = a.count
        return n % 2 == 1 ? a[n / 2] : (a[n / 2 - 1] + a[n / 2]) / 2
    }

    /// 0...100, nil with no score at all
    static func quality(_ id: String, _ lang: String) -> Int? {
        var a = pool(id, lang, "q")
        if lang != "hr", let b = Bench.pct(id) { a.append(Double(b)) }
        guard !a.isEmpty else { return nil }
        return Int((a.reduce(0, +) / Double(a.count)).rounded())
    }
    static func qualitySamples(_ id: String, _ lang: String) -> Int { pool(id, lang, "q").count }

    static func stars(_ pct: Int) -> String {
        let n = max(1, min(5, Int((Double(pct) / 20).rounded())))
        return String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
    }

    /// " · 1.0 s · ★★★★☆", " · 1.0 s · no rating yet", " · no time yet · ★★★☆☆" or " · no data yet"
    static func tag(_ id: String, _ lang: String) -> String {
        let m = median(id, lang), q = quality(id, lang)
        if m == nil && q == nil { return " · no data yet" }
        let t = m.map { String(format: "%.1f s", $0) } ?? "no time yet"
        let s = q.map { stars($0) } ?? "no rating yet"
        return " · \(t) · \(s)"
    }

    /// the engine's name with its speed and quality: "Deepgram · 1.0 s · ★★★★☆" (long: the catalogue's full name)
    static func name(_ s: EngineSpec, _ lang: String, long: Bool = false) -> String { (long ? s.name : s.short) + tag(s.id, lang) }

    /// the title stored in History ("Groq turbo EN") shown with its tag; anything else comes back as it is
    static func decorate(hear: String) -> String {
        for s in Catalog.all {
            for l in HearEngine.langs where s.short + " " + l.uppercased() == hear { return hear + tag(s.id, l) }
        }
        return hear
    }
    static func engineId(hear: String) -> (String, String)? {
        for s in Catalog.all {
            for l in HearEngine.langs where s.short + " " + l.uppercased() == hear { return (s.id, l) }
        }
        return nil
    }

    // MARK: TEST mode: a known sentence is spoken, each engine's text is compared to it by WER
    static var testOn: Bool {
        get { UserDefaults.standard.bool(forKey: "statsTest") }
        set { UserDefaults.standard.set(newValue, forKey: "statsTest") }
    }
    static var reference: String {
        get { UserDefaults.standard.string(forKey: "statsReference") ?? defaultReference }
        set { UserDefaults.standard.set(newValue, forKey: "statsReference") }
    }

    /// after every successful take (Chain.run): the time, and in TEST mode the WER score when the take was the reference
    /// (a take that has under 30 % of it is something else Marko said, and is not scored)
    static func afterTake(_ id: String, _ lang: String, text: String, secs: Double) {
        recordTime(id, lang, secs)
        guard testOn else { return }
        let pct = Scores.accuracy(reference: reference, heard: text)
        if pct >= 30 { recordQuality(id, lang, pct); appendLog("stats: \(id) \(lang) test score \(pct)% against the reference") }
    }

    /// the first run of v24: what the live test of 15.11.2026 already measured (enginetest.tsv)
    static func seedOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "statsSeeded24") else { return }
        d.set(true, forKey: "statsSeeded24")
        for (secs, text) in [(2.7, "This is a Test Stream recording of the concert of 1710, 2026 Česki dom narodni Zagreb."),
                             (0.4, "This is a test stream recording of the concert of seventh ten, Cheshki Dom, Zagreb."),
                             (0.4, "This is a test stream recording of the concert seventeenth ten, twenty twenty six Cheškin Arand in Dun Zagreb.")] {
            recordTime("parakeet", "en", secs)
            recordQuality("parakeet", "en", Scores.accuracy(reference: defaultReference, heard: text))
        }
        recordTime("whisper", "en", 1.6)
        appendLog("stats: seeded from the live test of 15.11.2026 (Parakeet 3 takes, Whisper 1)")
    }

    /// for /engines
    static func json(_ id: String, _ lang: String) -> [String: Any] {
        var o: [String: Any] = ["takes": samples(id, lang), "rated_takes": qualitySamples(id, lang)]
        if let m = median(id, lang) { o["median_secs"] = (m * 100).rounded() / 100 }
        if let q = quality(id, lang) { o["quality_pct"] = q; o["stars"] = stars(q) }
        return o
    }
}
