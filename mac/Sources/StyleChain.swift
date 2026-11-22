import Foundation

// v66, Marko, 22.11.2026: "In blob, there is a style button. It's supposed to style anything which is inside the text box, but
// it doesn't do it. ... make a fallback. First styling is coming with Opus, and second styling is coming with Groq. So one of
// these two must work."
//
// The STYLE button's model walk: Claude (Opus unless Settings names another) first, Groq second. An attempt fails on an error,
// a timeout, an empty answer, or an answer that is clearly not the same message (a refusal, an answer to it, much longer, in
// another language, a "Here is ..." preface). Then the next one runs. When both fail nothing is written; the reason of each is
// said in the pill and every attempt has a line in the log. The pure parts (check, run) are tested by `--selftest` in the CI.
enum StyleChain {
    struct Step { let name: String; let seconds: Double; let run: (String) -> Result<String, EngineError> }
    struct Report { var styled: String?; var by: String?; var attempts: [String]; var failure: String? }
    typealias Bound = (Double, @escaping () -> Result<String, EngineError>) -> Result<String, EngineError>?

    /// work on another thread, waited for at most `secs`; nil when it did not finish (it is left to end alone)
    static let bounded: Bound = { secs, work in
        var out: Result<String, EngineError>? = nil
        let lock = NSLock(), sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { let r = work(); lock.lock(); out = r; lock.unlock(); sem.signal() }
        guard sem.wait(timeout: .now() + secs) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return out
    }

    static func run(_ input: String, steps: [Step], bound: Bound = StyleChain.bounded) -> Report {
        var rep = Report(styled: nil, by: nil, attempts: [], failure: nil)
        for s in steps {
            let t0 = Date()
            guard let r = bound(s.seconds, { s.run(input) }) else {
                rep.attempts.append("\(s.name): no answer in \(Int(s.seconds)) s"); continue
            }
            switch r {
            case .failure(let e): rep.attempts.append("\(s.name): \(e.message)")
            case .success(let out):
                if let why = check(input, out) { rep.attempts.append("\(s.name): answer refused (\(why))"); continue }
                rep.styled = out; rep.by = s.name
                rep.attempts.append("\(s.name): ok in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
                return rep
            }
        }
        rep.failure = rep.attempts.joined(separator: " · ")
        return rep
    }

    // MARK: is this still the same message?

    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
    }
    private static func looksCroatian(_ s: String) -> Bool { s.range(of: "[čćšžđČĆŠŽĐ]", options: .regularExpression) != nil }
    private static func looksEnglish(_ s: String) -> Bool {
        let w = Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return w.intersection(["the", "and", "you", "that", "this", "with", "have", "for", "are", "was", "please"]).count >= 2
    }

    /// nil = the answer is the message, styled; else the reason it is not
    static func check(_ input: String, _ output: String) -> String? {
        let o = output.trimmingCharacters(in: .whitespacesAndNewlines), i = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if o.isEmpty { return "empty" }
        if o.count > i.count * 3 + 40 { return "much longer than the message" }
        let low = o.lowercased(), lowIn = i.lowercased()
        for p in ["i can't", "i cannot", "i'm sorry", "i am sorry", "sorry,", "as an ai", "i'm unable", "ne mogu ", "žao mi je"]
        where low.hasPrefix(p) && !lowIn.hasPrefix(p) { return "a refusal" }
        if let first = low.split(separator: "\n").first, first.hasSuffix(":"),
           ["here is", "here's", "sure", "okay", "of course", "evo ", "naravno"].contains(where: { first.hasPrefix($0) }), !lowIn.hasPrefix(String(first.prefix(4))) {
            return "a preface instead of the message"
        }
        if looksCroatian(i) && !looksCroatian(o) && o.count > 40 && !looksEnglish(i) { return "another language" }
        if !looksCroatian(i) && looksEnglish(i) && looksCroatian(o) { return "another language" }
        let wi = words(i)
        if wi.count >= 4 {
            let wo = Set(words(o))
            let kept = Double(wi.filter { wo.contains($0) }.count) / Double(wi.count)
            if kept < 0.4 { return "not the same message (\(Int(kept * 100)) % of its words)" }
        }
        return nil
    }

    static func wrap(_ s: String) -> String { "<message>\n" + s + "\n</message>" }
    static func unwrap(_ s: String) -> String {
        s.replacingOccurrences(of: "</?message>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: the two real providers

    /// Claude's family from Settings (Opus by default), then Groq
    static func steps(lang: String, mode: TextMode, first: StyleEngine) -> [Step] {
        [Step(name: first.title.replacingOccurrences(of: "Claude ", with: ""), seconds: 9) { text in
                Claude.style(wrap(text), lang: lang, family: first.rawValue, mode: mode).map(unwrap).map(corrected).map(Style.noEmptyLines) },
         Step(name: "Groq", seconds: 9) { text in
                GroqStyle.style(wrap(text), lang: lang, mode: mode).map(unwrap).map(corrected).map(Style.noEmptyLines) }]
    }
}

// MARK: Groq (OpenAI-compatible chat), the key ring the engines already use (numbered keys, failover)

enum GroqStyle {
    static let preferred = ["openai/gpt-oss-120b", "qwen/qwen3.8-27b", "openai/gpt-oss-20b"]
    static let skip = ["whisper", "orpheus", "guard", "safeguard", "allam", "tts"]

    static func request(_ path: String, key: String, body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1" + path)!)
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("curl/8", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    /// the best text model the ring's account lists today, asked once a day
    static func model(_ key: String) -> String? {
        let d = UserDefaults.standard
        if let m = d.string(forKey: "groqChatModel"), let at = d.object(forKey: "groqChatModelAt") as? Date, Date().timeIntervalSince(at) < 86400 { return m }
        let r = call(request("/models", key: key), timeout: 8)
        let ids = ((json(r.data)["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        let usable = ids.filter { id in !skip.contains(where: { id.lowercased().contains($0) }) }
        let pick = preferred.first(where: { ids.contains($0) }) ?? usable.first
        guard let m = pick else { return d.string(forKey: "groqChatModel") }
        d.set(m, forKey: "groqChatModel"); d.set(Date(), forKey: "groqChatModelAt")
        return m
    }

    static func style(_ text: String, lang: String, mode: TextMode) -> Result<String, EngineError> {
        let s = Rules.system(lang: lang, mode: mode)
        return Ring.run(.groq) { key -> Ring.Outcome<String> in
            guard let model = model(key) else { return .fail(Failure(status: 401, body: "no Groq text model listed for this key", headers: [:])) }
            var body: [String: Any] = ["model": model, "temperature": 0.2, "max_completion_tokens": 3000,
                                       "messages": [["role": "system", "content": s.fixed + "\n\n" + s.tail], ["role": "user", "content": text]]]
            if model.contains("gpt-oss") { body["reasoning_effort"] = "low" }
            return .from(call(request("/chat/completions", key: key, body: body), timeout: 9)) { d in
                let msg = ((json(d)["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
                let t = msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return t.isEmpty ? nil : t
            }
        }
    }
}
