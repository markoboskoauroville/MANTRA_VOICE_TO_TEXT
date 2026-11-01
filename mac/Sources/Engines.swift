// The engines of Marko Transcribe (Mantra): the ones that hear and the ones that style.
//
// Marko, 18.10.2026: "under one roof have Speechify and local and easily switch it with mouse. Also, we need to use API
// calls to Haiku from Anthropic ... or ... alternatives which can be almost free or free which can apply the style to my
// transcribed text and by applying the style correct any misspelling by the engine."
//
// Roles, not names (MANTRA_MANIFEST modules/provider-router.md): the stripe asks for "hear" and "style"; which engine
// does each is a choice on the stripe, remembered.
import Foundation

let appVersion = 5

// MARK: the choices

// ONLY WHISPER AND ANTHROPIC (Marko, 30.10.2026: "strip all out, only Whisper model turbo and models from Anthropic for
// style correction ... simplify code, support only Whisper and Anthropic and that is all"). Speechify, Groq, AssemblyAI,
// the local style model and the quick choices are gone from the app and from its code.

// the transcription model: Whisper large-v3-turbo on this Mac, told which language to listen for
// v15 (Marko, 31.10.2026: "should be Whisper Turbo Auto which works with Croatian and English at the same time"):
// AUTO lets Whisper find the language of each take, held to Croatian or English (MANTRA_VOICE ears.py, lang=auto).
enum HearEngine: String, CaseIterable {
    case whisperEN, whisperHR, whisperAuto

    var title: String {
        switch self { case .whisperEN: return "Whisper Turbo EN"; case .whisperHR: return "Whisper Turbo HR"; case .whisperAuto: return "Whisper Turbo AUTO" }
    }
    var menuTitle: String {
        switch self {
        case .whisperEN: return "Whisper Turbo, English"
        case .whisperHR: return "Whisper Turbo, Croatian"
        case .whisperAuto: return "Whisper Turbo, Auto (Croatian and English)"
        }
    }
    var lang: String { switch self { case .whisperEN: return "en"; case .whisperHR: return "hr"; case .whisperAuto: return "auto" } }

    static var current: HearEngine {
        get { HearEngine(rawValue: UserDefaults.standard.string(forKey: "hear") ?? "") ?? .whisperEN }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hear") }
    }
}

// the correction: a Claude model at Anthropic, by its family (the newest of it, asked once a day), or none
enum StyleEngine: String, CaseIterable {
    case off, haiku, sonnet, opus

    var title: String {
        switch self {
        case .off: return "no auto correct"
        case .haiku: return "Claude Haiku"
        case .sonnet: return "Claude Sonnet"
        case .opus: return "Claude Opus"
        }
    }
    var menuTitle: String {
        switch self {
        case .off: return "None"
        case .haiku: return "Claude Haiku (fastest)"
        case .sonnet: return "Claude Sonnet"
        case .opus: return "Claude Opus (best)"
        }
    }

    static var current: StyleEngine {
        get { StyleEngine(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? (Keys.get(.anthropic).isEmpty ? .off : .haiku) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "style") }
    }
}

// v19, THE STYLE BUTTON'S OWN CLAUDE (Marko, 31.10.2026: "In settings it needs to have default engine for Anthropic when
// I click the style manually in the user interface. And this styling works always."): a choice of its own, never None,
// independent of the correction after a take. Haiku by default, the app's standard (StyleEngine.current's default).
enum StyleButtonEngine {
    static let choices: [StyleEngine] = [.haiku, .sonnet, .opus]
    static var current: StyleEngine {
        get {
            let e = StyleEngine(rawValue: UserDefaults.standard.string(forKey: "styleButton") ?? "") ?? .haiku
            return e == .off ? .haiku : e
        }
        set { UserDefaults.standard.set((newValue == .off ? StyleEngine.haiku : newValue).rawValue, forKey: "styleButton") }
    }
}

enum Prefs {
    // v22: the status line below the pill instead of above (a short click on it flips it)
    static var lineBelow: Bool {
        get { UserDefaults.standard.bool(forKey: "lineBelow") }
        set { UserDefaults.standard.set(newValue, forKey: "lineBelow") }
    }
    static var names: String {                       // v3: names the correction spells right (Marko's came over)
        get { UserDefaults.standard.string(forKey: "names") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "names") }
    }
    static var extra: String {                       // "in settings I can also add some things to it"
        get { UserDefaults.standard.string(forKey: "extra") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "extra") }
    }
    // Request 10: "f1 pops up window f1 again hides it after 2 second delay ... esc same": the stripe minimizes 2 s after
    // each take unless he turns this off in ⚙.
    static var autoHide: Bool {
        get { UserDefaults.standard.object(forKey: "autoHide") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoHide") }
    }
    // v15 (Marko, 31.10.2026: "in the settings I want to have adjustments for sound level of sound for stopping and
    // starting recording"): 0…1 each, the sound's own volume
    /// v25: once, both sliders to 100 % = Speechify's own level (the old positions meant amplitude, v24 made them
    /// decibels: 40 % and 17 % would have played at -24 and -33 dB)
    static var startVolume: Float {
        get { UserDefaults.standard.object(forKey: "startVolume") as? Float ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "startVolume") }
    }
    static var stopVolume: Float {
        get { UserDefaults.standard.object(forKey: "stopVolume") as? Float ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "stopVolume") }
    }
}

struct EngineError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

// One HTTP request, waited for (called off the main thread).
func send(_ req: URLRequest, timeout: TimeInterval = 120) -> (status: Int, data: Data?, error: String?) {
    var r = req
    r.timeoutInterval = timeout
    var out: (Int, Data?, String?) = (0, nil, nil)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: r) { data, resp, err in
        out = ((resp as? HTTPURLResponse)?.statusCode ?? 0, data, err?.localizedDescription)
        done.signal()
    }.resume()
    done.wait()
    return out
}

func json(_ d: Data?) -> [String: Any] { (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:] }

// MARK: the standing corrections (MANTRA_MANIFEST modules/transcription.md), applied in code before and after any model:
// in the first tests every model kept "Grok" (it is also a real product) and the small one kept "Amarco".

// v3 (one app, Marko 1.11.2026): the corrections are a file of the person's own, one "pattern => text" a line
// (regular expressions), in Application Support/Voice to Text (Mantra)/corrections.txt; Marko's ("Marco" → "Marko")
// came over from Transcribe Voice to Text RT (Merge.swift). No file, no corrections.
let corrections: [(NSRegularExpression, String)] = {
    guard let t = try? String(contentsOf: appSupport.appendingPathComponent("corrections.txt"), encoding: .utf8) else { return [] }
    return t.split(separator: "\n").compactMap { line in
        let parts = line.components(separatedBy: " => ")
        guard parts.count == 2, !line.hasPrefix("#"), let re = try? NSRegularExpression(pattern: parts[0]) else { return nil }
        return (re, parts[1])
    }
}()

func corrected(_ text: String) -> String {
    var s = text
    for (re, right) in corrections {
        s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: right)
    }
    return s
}

// MARK: hearing

// What Whisper writes for a quiet take that has no speech in it (it learned them from subtitles); alone, they are dropped.
let inventions: Set<String> = ["you", "thank you", "thank you.", "thanks for watching", "thanks for watching!", "bye", "hvala",
                               "hvala.", "hvala vam", "hvala na gledanju", ".", ""]

enum Hear {
    /// the language Whisper heard in the last take ("en" / "hr"), when the voice says it (lang=auto)
    static var lastLang: String?

    static func run(_ engine: HearEngine, wav: URL) -> Result<String, EngineError> {
        let r = heard(engine, wav: wav)
        if case .success(let t) = r, inventions.contains(t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            return .failure(EngineError("nothing said (Whisper heard only \"\(t)\")"))
        }
        return r
    }

    static func heard(_ engine: HearEngine, wav source: URL) -> Result<String, EngineError> {
        if Ears.current == .server { return Ears.server(source, lang: engine.lang) }
        let r = Whisper.transcribe(source, lang: engine.lang)
        lastLang = Whisper.lastLang
        return r
    }
}

// MARK: styling: the rules (kept the same as server/styled.py RULES; the language rule last, named)

enum Rules {
    static let base = """
    You clean up a message that a person dictated and a speech recogniser wrote down. Reply with the cleaned message only, nothing before or after it.

    This is an edit, not a summary. Keep their sentences, their words and their order. Only remove what is repeated and fix what is wrong.

    Keep their point of view exactly: "I", "me", "my" stay "I", "me", "my", and "you" stays "you". A request stays a request, with its "please" and its "if you can". A wish stays a wish ("volio bih" stays "volio bih"). Never change who does what.

    Fix the words the recogniser misheard: choose the word that makes sense in the sentence. Fix spelling, grammar and punctuation in the language of the message. Every sentence starts with a capital letter, names have capitals.

    Remove repetitions, false starts ("no wait") and filler words (um, uh, you know, like, I mean, ono, ovaj, znači, dakle). When they say the same thing twice, keep it once. When an explanation is confused, say it once, clearly, in the order that makes sense.

    Keep every fact, name, number, date, request and decision. Add nothing they did not say. Do not soften what they said firmly and do not make firmer what they said gently. Keep English words mixed into Croatian.

    Style: short paragraphs of one or two sentences. Plain everyday words. Written to one person as "you". The reason comes before the request. Warm, never gushing.

    Never use dashes, bullet points, headings, bold, exclamation marks or emoji. Normal sentence capitals and correct apostrophes.

    """

    // The fixed part first (so a cache can hold it), then his additions, then the language, named.
    static func system(lang: String) -> (fixed: String, tail: String) {
        var tail = ""
        if !Prefs.names.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tail += "Names, spelled like this: \(Prefs.names)\n\n" }
        if !Prefs.extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tail += "Also, from the person: \(Prefs.extra)\n\n" }
        if lang == "auto" {                                    // v15: Whisper Turbo Auto, the language not named by the voice
            tail += "The message is in Croatian or in English, or mixes both. Write each part in the language it is in, and in no other language."
        } else {
            let name = lang == "hr" ? "Croatian" : "English"
            tail += "The message is in \(name). Write the result in \(name) and in no other language."
        }
        return (base, tail)
    }
}

enum Style {
    static func run(_ engine: StyleEngine, text: String, lang: String) -> Result<String, EngineError> {
        let input = corrected(text)
        guard engine != .off else { return .success(input) }
        return Claude.style(input, lang: lang, family: engine.rawValue).map(corrected)
    }
}

// MARK: Claude (Anthropic Messages API, plain HTTPS: there is no Swift SDK)

enum Claude {
    static let base = "https://api.anthropic.com/v1"

    static func request(_ path: String, key: String, body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: base + path)!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    // THE MODEL BY ITS FAMILY (MANTRA_MANIFEST modules/model-names.md: "Never hardcode a model version"): the newest
    // haiku, sonnet or opus the API lists, asked once a day and remembered.
    static func model(_ key: String, family: String = "haiku") -> String? {
        let d = UserDefaults.standard
        if let m = d.string(forKey: family + "Model"), let at = d.object(forKey: family + "ModelAt") as? Date,
           Date().timeIntervalSince(at) < 86400 { return m }
        let r = send(request("/models?limit=100", key: key), timeout: 20)
        let list = (json(r.data)["data"] as? [[String: Any]]) ?? []
        let same = list.filter { ($0["id"] as? String)?.contains(family) ?? false }
        guard let newest = same.max(by: { ($0["created_at"] as? String ?? "") < ($1["created_at"] as? String ?? "") })?["id"] as? String
        else { return d.string(forKey: family + "Model") }
        d.set(newest, forKey: family + "Model"); d.set(Date(), forKey: family + "ModelAt")
        return newest
    }

    static func style(_ text: String, lang: String, family: String) -> Result<String, EngineError> {
        let s = Rules.system(lang: lang)
        return Ring.run(.anthropic) { key -> Ring.Outcome<String> in
            guard let model = model(key, family: family) else { return .fail(Failure(status: 401, body: "no \(family) model listed for this key", headers: [:])) }
            let body: [String: Any] = [
                "model": model, "max_tokens": 4096,
                "output_config": ["effort": "low"],                 // a short rewrite: little thinking
                "system": [["type": "text", "text": s.fixed, "cache_control": ["type": "ephemeral"]],   // the fixed rules, cached
                           ["type": "text", "text": s.tail]],
                "messages": [["role": "user", "content": text]],
            ]
            return .from(call(request("/messages", key: key, body: body))) { d in
                let j = json(d)
                if j["stop_reason"] as? String == "refusal" { return "" }
                let t = ((j["content"] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }.joined()
                return t.isEmpty ? nil : t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.flatMap { $0.isEmpty ? .failure(EngineError("Claude declined this message")) : .success($0) }
    }
}

// MARK: TEST (the button, keyring.md §6: a person asking is not the app guessing). Every key asked to do the smallest
// billable thing its provider sells (key-testing.md §3); the five states a person sees (§6).

enum KeyTest {
    static func probe(_ p: Provider, _ key: String) -> Failure? {
        guard let model = Claude.model(key) else { return Failure(status: 401, body: "no model listed", headers: [:]) }
        let r = call(Claude.request("/messages", key: key, body: ["model": model, "max_tokens": 1, "messages": [["role": "user", "content": "hi"]]]), timeout: 20)
        return r.status == 200 ? nil : Failure(status: r.status, body: String(data: r.data, encoding: .utf8) ?? r.error ?? "", headers: r.headers)
    }

    static func word(_ v: Verdict) -> String {
        switch v { case .ok: return "works"; case .dead: return "rejected"; case .noCredit: return "no credit"; case .cool: return "throttled"; case .soft: return "unclear" }
    }

    // every key of the provider, a few at a time; the ring learns each answer
    static func run(_ p: Provider) -> String {
        let keys = Keys.entries(p)
        guard !keys.isEmpty else { return "no key" }
        var counts: [Verdict: Int] = [:]
        var lines: [String] = []
        let q = DispatchQueue(label: "keytest"), group = DispatchGroup(), gate = DispatchSemaphore(value: 5)
        for k in keys {
            group.enter(); gate.wait()
            DispatchQueue.global().async {
                let f = probe(p, k.key)
                let v = f.map(Classify.verdict) ?? .ok
                Ring.mark(p, k, v, f?.short ?? "works", rest: v == .cool ? f.map(Classify.rest) : nil)
                q.sync { counts[v, default: 0] += 1; if v != .ok { lines.append("\(k.title): \(word(v)) (\(f?.short ?? ""))") } }
                gate.signal(); group.leave()
            }
        }
        group.wait()
        let order: [Verdict] = [.ok, .noCredit, .dead, .cool, .soft]
        let summary = order.compactMap { v in counts[v].map { "\($0) \(word(v))" } }.joined(separator: " · ")
        appendLog("key test \(p.rawValue): \(summary)" + (lines.isEmpty ? "" : "; " + lines.joined(separator: "; ")))
        return "\(summary) of \(keys.count)"
    }
}

