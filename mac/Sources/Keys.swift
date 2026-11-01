// THE KEY RING (request 17, Marko 19.10.2026: "make sure the all APIs has a fallback mechanism so they are compatible with
// multiple APIs in one file"). Every provider the app calls (since 30.10.2026 only Anthropic) holds a ring of keys, read from
// his own key notes by SHAPE, each with the title written above it, and walked by one ring that every engine shares.
// The rules are MANTRA_MANIFEST modules/keyring.md and quota-and-fallback.md, ported from TTT Mini (MaKeyRing.kt) and
// MAHA_TRANSCRIBE_STREAMLIT (ttt/keyring.py):
//
//   never test speculatively      the first usable key does the real work; a dead key costs one call in its life
//   one key per JOB               AssemblyAI's upload, submit and poll stay on one account (an upload belongs to it)
//   read the body, not the code   401/403 dead · 429 rests for what Retry-After says · money words: no credit ·
//                                 403 + Cloudflare 1010, 400, 404, 5xx: OUR fault or theirs, the ring stops
//   the ring never comes back empty  dead and resting keys are tried last, never skipped for good
//   it says so when it moves      the stripe and the log name the key that took over (by its title, never the key)
//
// WHY NOT THE KEYCHAIN (18.10.2026, "explain why this pop up comming again and again"): a Keychain item remembers the
// app that made it by its partition; an app signed by a registered developer is known by its team, but "Mantra Apps" is
// our own certificate with no team, so macOS knows the app only by the fingerprint of its program, which changes with
// every build. Each build asked for the login password again. The keys live in a file only his account can read (0600);
// the ring's memory holds fingerprints and titles, never a key.
import Foundation
import CryptoKit

// only Anthropic (30.10.2026): the keys of the correction; Whisper runs on this Mac and needs none
enum Provider: String, CaseIterable {
    case anthropic

    var title: String { "Anthropic" }
    var pattern: String { #"sk-ant-[A-Za-z0-9_\-]{20,}"# }
    var shapeHint: String { "Anthropic keys start with sk-ant-." }
}

let appSupport: URL = {
    let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let new = base.appendingPathComponent("Voice to Text (Mantra)"), old = base.appendingPathComponent("Mantra Voice to Text")
    // v2 renamed the app (Marko, 1.11.2026): the v1 folder (the model, a half download, the key, the history) moves once
    if !FileManager.default.fileExists(atPath: new.path) && FileManager.default.fileExists(atPath: old.path) {
        try? FileManager.default.moveItem(at: old, to: new)
    }
    return new
}()

struct KeyEntry: Codable, Equatable {
    var key: String
    var title: String
}

// MARK: the store

enum Keys {
    static let folder = appSupport
    static let file = folder.appendingPathComponent("keys.json")
    private static var cache: [String: [KeyEntry]]?
    private static let lock = NSLock()

    private static func all() -> [String: [KeyEntry]] {
        if let c = cache { return c }
        let data = try? Data(contentsOf: file)
        var d: [String: [KeyEntry]] = [:]
        if let data, let v = try? JSONDecoder().decode([String: [KeyEntry]].self, from: data) { d = v }
        // keyring.md §8 test 4, the upgrade: v2–v6 kept plain keys, [provider: [key]]; they are read and kept, untitled
        else if let data, let old = try? JSONDecoder().decode([String: [String]].self, from: data) {
            d = old.mapValues { $0.enumerated().map { KeyEntry(key: $1, title: "key \($0 + 1)") } }
        }
        cache = d
        return d
    }

    static func entries(_ p: Provider) -> [KeyEntry] { lock.lock(); defer { lock.unlock() }; return all()[p.rawValue] ?? [] }
    static func get(_ p: Provider) -> [String] { entries(p).map(\.key) }

    @discardableResult
    static func set(_ p: Provider, _ list: [KeyEntry]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var d = all()
        d[p.rawValue] = list.isEmpty ? nil : list
        cache = d
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(d), (try? data.write(to: file, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return true
    }

    // Keys found in a file are added after the ones already held, each once (keyring.md §4: de-duplicate on import);
    // a key already held gets the file's title when it had none.
    static func add(_ p: Provider, _ found: [KeyEntry]) -> Int {
        var have = entries(p)
        var new = 0
        for f in found {
            if let i = have.firstIndex(where: { $0.key == f.key }) {
                if have[i].title.hasPrefix("key ") && !f.title.hasPrefix("key ") { have[i].title = f.title }
            } else { have.append(f); new += 1 }
        }
        set(p, have)
        return new
    }

    // MARK: the parser (keyring.md §4, §6b, §10d): blocks split on blank lines, the key by SHAPE, the title by elimination:
    // the first line of the block that holds no key, with every key shape taken out of it.

    static func parse(_ text: String, sourceName: String, only: Provider? = nil) -> [Provider: [KeyEntry]] {
        var out: [Provider: [KeyEntry]] = [:]
        let blocks = text.components(separatedBy: .newlines).split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        for block in blocks {
            let lines = block.map { String($0) }
            let joined = lines.joined(separator: "\n")
            for p in Provider.allCases where only == nil || only == p {
                let found = matches(p.pattern, in: joined).filter { k in !(out[p] ?? []).contains { $0.key == k } }
                guard !found.isEmpty else { continue }
                let title = lines.map(stripKeys).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t:#-=*")) }
                    .first { !$0.isEmpty && $0.count <= 60 } ?? ""
                for (i, k) in found.enumerated() {
                    let t = title.isEmpty ? "" : (found.count > 1 ? "\(title) \(i + 1)" : title)
                    out[p, default: []].append(KeyEntry(key: k, title: t))
                }
            }
        }
        // untitled keys are named by their place in the file
        for (p, list) in out {
            out[p] = list.enumerated().map { $1.title.isEmpty ? KeyEntry(key: $1.key, title: "key \($0 + 1)") : $1 }
        }
        return out
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>(), out: [String] = []
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let k = String(text[r])
            if seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    // a title can never contain a key (keyring.md §6b, the ring.py _label_from bug)
    static func stripKeys(_ line: String) -> String {
        var s = line
        for p in Provider.allCases {
            s = s.replacingOccurrences(of: p.pattern, with: "", options: .regularExpression)
        }
        return s.replacingOccurrences(of: #"[0-9A-Za-z_\-\.]{28,}"#, with: "", options: .regularExpression)
    }

    // THE FILE PICKER'S ANSWER (keyring.md §6b "a sentence back"): what was read from each file, sorted by shape.
    static func importFiles(_ urls: [URL], only: Provider? = nil) -> String {
        var lines: [String] = []
        for url in urls {
            guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                lines.append("\(url.lastPathComponent): not a text file"); continue
            }
            let found = parse(text, sourceName: url.lastPathComponent, only: only)
            if found.isEmpty {
                lines.append("\(url.lastPathComponent): no key found in it" + (only.map { " (\($0.shapeHint))" } ?? "")); continue
            }
            var parts: [String] = []
            for p in Provider.allCases {
                guard let list = found[p] else { continue }
                let new = add(p, list)
                parts.append("\(list.count) \(p.title) key\(list.count == 1 ? "" : "s")" + (new < list.count ? " (\(list.count - new) already held)" : ""))
            }
            lines.append("\(url.lastPathComponent): " + parts.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    static func forget(_ p: Provider) { set(p, []); Ring.reset(p) }
}

// MARK: the verdict (quota-and-fallback.md §3, key-testing.md §5): one classifier for every provider

enum Verdict: String, Codable {
    case ok          // it did the work
    case dead        // the key is refused: revoked, wrong
    case noCredit    // the key is real, the account is empty: top it up
    case cool        // throttled this minute: rest, never bury
    case soft        // our request, their outage, Cloudflare, the internet: not the key, the ring stops
}

struct Failure {
    let status: Int
    let body: String
    let headers: [AnyHashable: Any]
    var short: String { status == 0 ? (body.isEmpty ? "no answer (the internet?)" : body) : "HTTP \(status)" + (message.isEmpty ? "" : " " + message) }
    var message: String {
        let j = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        let e = j["error"]
        let m = (e as? String) ?? ((e as? [String: Any])?["message"] as? String) ?? (j["message"] as? String) ?? String(body.prefix(120))
        return String(m.prefix(140))
    }
}

enum Classify {
    static let waitHints = ["retrydelay", "retry-after", "per minute", "rate limit", "try again in", "rate_limit"]
    static let strongMoney = ["credit", "e0300", "zero_credits", "balance", "depleted", "insufficient", "billing", "payment",
                              "out of funds", "upgrade your plan", "prepayment", "account is not active"]
    static let weakMoney = ["quota", "exhausted", "resource_exhausted", "free tier", "plan limit"]

    static func verdict(_ f: Failure) -> Verdict {
        let b = f.body.lowercased()
        let hasWait = waitHints.contains { b.contains($0) } || header(f.headers, "retry-after") != nil
        let money = strongMoney.contains { b.contains($0) } || (!hasWait && weakMoney.contains { b.contains($0) })
        switch f.status {
        case 0: return .soft                                      // the internet: another key will not help
        case 403 where b.contains("1010"): return .soft           // Cloudflare refusing the client, not the key
        case 403 where b.contains("cannot access uploaded file"): return .soft   // our routing (keyring.md §2b)
        case 401, 403: return money ? .noCredit : .dead
        case 402: return .noCredit
        case 429: return hasWait || !money ? .cool : .noCredit
        case 400: return money ? .noCredit : .soft
        default: return .soft                                     // 404, 5xx, anything unknown: stop, blame nobody
        }
    }

    // How long to rest a throttled key: what the provider said, floor 1 s, ceiling 1 h (quota-and-fallback.md §4)
    static func rest(_ f: Failure) -> TimeInterval {
        var s: Double = 60
        if let v = header(f.headers, "retry-after"), let n = Double(v) { s = n }
        else if let v = header(f.headers, "x-ratelimit-reset-requests") ?? header(f.headers, "x-ratelimit-reset-tokens") { s = duration(v) ?? 60 }
        return min(max(s, 1), 3600)
    }

    static func header(_ h: [AnyHashable: Any], _ name: String) -> String? {
        for (k, v) in h where (k as? String)?.lowercased() == name { return "\(v)" }
        return nil
    }

    // "44m38.4s", "547ms", "2"
    static func duration(_ s: String) -> Double? {
        if let n = Double(s) { return n }
        var total = 0.0, num = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isNumber || c == "." { num.append(c) }
            else if s[i...].hasPrefix("ms") { total += (Double(num) ?? 0) / 1000; num = ""; i = s.index(after: i) }
            else if c == "h" { total += (Double(num) ?? 0) * 3600; num = "" }
            else if c == "m" { total += (Double(num) ?? 0) * 60; num = "" }
            else if c == "s" { total += Double(num) ?? 0; num = "" }
            i = s.index(after: i)
        }
        return total > 0 ? total : nil
    }
}

// MARK: the ring

enum Ring {
    struct State: Codable {
        var verdict: Verdict
        var at: Date
        var until: Date?             // a resting or empty key is asked again after this
        var detail: String
    }
    struct Memory: Codable {
        var current: String?         // fingerprint of the key in use: the next job starts there
        var states: [String: State] = [:]
    }

    static let file = Keys.folder.appendingPathComponent("ring.json")
    private static let lock = NSLock()
    private static var mem: [String: Memory]?
    // the last time the ring moved, said once on the stripe (best practice rule 5: say it out loud)
    static var lastMove: String?

    static func fingerprint(_ key: String) -> String {
        String(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    private static func load() -> [String: Memory] {
        if let m = mem { return m }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let m = (try? Data(contentsOf: file)).flatMap { try? dec.decode([String: Memory].self, from: $0) } ?? [:]
        mem = m
        return m
    }
    private static func save(_ m: [String: Memory]) {
        mem = m
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        guard let d = try? enc.encode(m) else { return }
        try? d.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func memory(_ p: Provider) -> Memory { lock.lock(); defer { lock.unlock() }; return load()[p.rawValue] ?? Memory() }
    static func reset(_ p: Provider) { lock.lock(); var m = load(); m[p.rawValue] = nil; save(m); lock.unlock() }
    static func revive(_ p: Provider) { lock.lock(); var m = load(); m[p.rawValue]?.states = [:]; save(m); lock.unlock() }

    static func usable(_ s: State?, now: Date = Date()) -> Bool {
        guard let s else { return true }
        switch s.verdict {
        case .ok, .soft: return true
        case .dead: return false
        case .cool, .noCredit: return (s.until ?? .distantPast) <= now
        }
    }

    // The order to try: the key in use, then his order, skipping the flagged; the flagged last, never left out.
    static func order(_ p: Provider) -> [KeyEntry] {
        let list = Keys.entries(p)
        let m = memory(p)
        var ordered = list
        if let cur = m.current, let i = ordered.firstIndex(where: { fingerprint($0.key) == cur }) {
            ordered = Array(ordered[i...]) + Array(ordered[..<i])
        }
        let good = ordered.filter { usable(m.states[fingerprint($0.key)]) }
        let flagged = ordered.filter { !usable(m.states[fingerprint($0.key)]) }
        return good + flagged
    }

    static func mark(_ p: Provider, _ k: KeyEntry, _ v: Verdict, _ detail: String, rest: TimeInterval? = nil, current: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        var m = all[p.rawValue] ?? Memory()
        let fp = fingerprint(k.key)
        var until: Date?
        if v == .cool { until = Date().addingTimeInterval(rest ?? 60) }
        if v == .noCredit { until = Date().addingTimeInterval(6 * 3600) }     // TTT Mini: topped up in a minute, so 6 h
        m.states[fp] = State(verdict: v, at: Date(), until: until, detail: detail)
        if current { m.current = fp }
        all[p.rawValue] = m
        save(all)
    }

    // the key's place in his list, "key 7 of 21" (keyring.md §10d: the position, never key material)
    static func place(_ p: Provider, _ k: KeyEntry) -> String {
        let list = Keys.entries(p)
        return "\(k.title), key \((list.firstIndex(of: k) ?? 0) + 1) of \(list.count)"
    }

    enum Outcome<T> { case ok(T), fail(Failure) }

    // One JOB per key: `job` does the whole lifecycle with the key it is given. Each key is tried at most once.
    // A SOFT failure (the internet dropped, their 5xx) is not the key's fault: it is not marked, and the next key tries
    // the job (request 19, Marko: "If one key is not working ... test another key ... don't fall back to Whisper only
    // if all AssemblyAI keys are not working"; 19.10.2026 three takes went to Whisper on one "SSL error" of key 1).
    // The key that works becomes the one in use and stays until it fails. Soft failures stop after `softBudget`
    // seconds so a dead internet does not hold the take for twenty timeouts; the caller then falls back.
    static let softBudget: TimeInterval = 60

    static func run<T>(_ p: Provider, _ job: (String) -> Outcome<T>) -> Result<T, EngineError> {
        let keys = order(p)
        guard !keys.isEmpty else { return .failure(EngineError("no \(p.title) key: paste one in ⚙ → Settings")) }
        var moved: [String] = []
        var last = ""
        let t0 = Date()
        // TEST MODE (request 19): `defaults write com.mantra.markotranscribe testDropKeys -int N` makes the first N keys
        // of every job lose the connection, as on 19.10.2026, so the walk past them can be seen without a real drop.
        let drop = UserDefaults.standard.integer(forKey: "testDropKeys")
        for (n, k) in keys.enumerated() {
            switch n < drop ? .fail(Failure(status: 0, body: "The network connection was lost. (test)", headers: [:])) : job(k.key) {
            case .ok(let v):
                mark(p, k, .ok, "worked", current: true)
                if n > 0 {
                    lastMove = "\(p.title): \(moved.joined(separator: ", ")); now \(k.title)"
                    appendLog("ring \(p.rawValue): \(lastMove!)")
                }
                return .success(v)
            case .fail(let f):
                let v = Classify.verdict(f)
                last = f.short
                appendLog("ring \(p.rawValue): \(place(p, k)) \(v.rawValue): \(f.short)")
                switch v {
                case .soft:
                    moved.append("\(k.title) \(f.status == 0 ? "no connection" : "failed")")
                    if Date().timeIntervalSince(t0) > softBudget {
                        return .failure(EngineError("\(p.title): \(n + 1) of \(keys.count) keys tried for \(Int(softBudget)) s, last: \(f.short)"))
                    }
                    if f.status == 0 { usleep(300_000) }      // let a dropped connection come back before the next key
                case .dead, .noCredit, .cool:
                    mark(p, k, v, f.short, rest: v == .cool ? Classify.rest(f) : nil)
                    moved.append("\(k.title) \(v == .dead ? "refused" : v == .noCredit ? "no credit" : "resting")")
                case .ok: break
                }
            }
        }
        return .failure(EngineError("\(p.title): all \(keys.count) keys unavailable, last: \(last)"))
    }
}

// The one HTTP call the ring's jobs make: the status, the body and the headers, a User-Agent always (Cloudflare 1010).
func call(_ req: URLRequest, timeout: TimeInterval = 120) -> (status: Int, data: Data, headers: [AnyHashable: Any], error: String?) {
    var r = req
    r.timeoutInterval = timeout
    if r.value(forHTTPHeaderField: "User-Agent") == nil { r.setValue("VoiceToTextMantra/\(appVersion) (macOS)", forHTTPHeaderField: "User-Agent") }
    var out: (Int, Data, [AnyHashable: Any], String?) = (0, Data(), [:], nil)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: r) { data, resp, err in
        let h = resp as? HTTPURLResponse
        out = (h?.statusCode ?? 0, data ?? Data(), h?.allHeaderFields ?? [:], err?.localizedDescription)
        done.signal()
    }.resume()
    done.wait()
    return out
}

extension Ring.Outcome {
    // a 200 the job cannot read is not the key's fault: it reaches the classifier as a 500 (soft)
    static func from(_ r: (status: Int, data: Data, headers: [AnyHashable: Any], error: String?), _ ok: (Data) -> T?) -> Ring.Outcome<T> {
        if r.status == 200, let v = ok(r.data) { return .ok(v) }
        let body = r.status == 0 ? (r.error ?? "") : String(data: r.data, encoding: .utf8) ?? ""
        return .fail(Failure(status: r.status == 200 ? 500 : r.status, body: body, headers: r.headers))
    }
}
