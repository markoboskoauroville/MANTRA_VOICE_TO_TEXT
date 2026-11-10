// KEYS ENTER ONLY THROUGH FILES, DETECTED BY SHAPE, TESTED FREE (ported from TTT's KeyScan / KeyTester / KeyImporter,
// builds 577-596, Marko 9-10.11.2026: "keys imported only from the key files ... detected by shape, tested free").
//
//   scan      every token of a file, its provider read from its shape (gsk_ Groq, AIza Google, sk-ant- Anthropic,
//             32 hex AssemblyAI or a Cloudflare account id, 40 hex Deepgram, 64 hex Soniox, 32 mixed letters Speechmatics,
//             sk_ ElevenLabs), a label in the file name or the line above wins over the shape
//   test      each new key asks its provider one free question (a list or an auth call, never a transcription: spend rule)
//   keep      only the working keys go into the ring, numbered in file order ("Groq 2/3"); a key that fails is dropped
//             and never printed. No key is ever shown, logged or committed: only its number and the last four characters.
import Foundation
import CryptoKit
import Security

enum KStatus { case working, limited, dead, noBalance, network }

enum KeyScan {
    struct Cand { let value: String; let kinds: [String] }

    static func full(_ s: String, _ pattern: String) -> Bool { s.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil }
    static func has(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }

    static let hex32 = "[0-9a-fA-F]{32}", hex40 = "[0-9a-fA-F]{40}", hex64 = "[0-9a-fA-F]{64}", alnum32 = "[A-Za-z0-9]{32}"
    static let google = "(AQ\\.[0-9A-Za-z._-]{20,}|AIza[0-9A-Za-z_-]{20,})"
    static let anthropic = "sk-ant-[0-9A-Za-z_-]{20,}"
    static let groq = "gsk_[0-9A-Za-z_-]{20,}"
    static let sku = "sk_[0-9A-Za-z_-]{16,}"
    static let cftoken = "cf[aut]t_[A-Za-z0-9_-]{20,}"
    static let notOurs = "^(gh[pousr]_|github_pat_|sk-|xox[a-z]-|AKIA|ya29\\.|rk_|pk_)[A-Za-z0-9_-]{6,}"
    static let separators = CharacterSet(charactersIn: " \t\r\n,;:\"'=|[](){}<>")
    static let hints: [(String, String)] = [
        ("groq", "groq"), ("deepgram", "deepgram"), ("assembly", "assemblyai"), ("speechmatics", "speechmatics"),
        ("soniox", "soniox"), ("eleven", "elevenlabs"), ("speechify", "speechify"), ("gemini", "google"),
        ("google", "google"), ("anthropic", "anthropic"), ("claude", "anthropic"), ("haiku", "anthropic"),
    ]

    static func hinted(_ ctx: String) -> [String] {
        var out: [String] = []
        for (word, kind) in hints where ctx.contains(word) && !out.contains(kind) { out.append(kind) }
        return out
    }

    static func tokenKinds(_ tok: String, _ ctx: String) -> [String] {
        let h = hinted(ctx)
        if full(tok, anthropic) { return ["anthropic"] }
        if full(tok, groq) { return ["groq"] }
        if full(tok, google) { return ["google"] }
        if full(tok, cftoken) { return ["cftoken"] }
        if full(tok, sku) {
            return h.contains("speechify") || (tok.count >= 44 && !h.contains("elevenlabs")) ? ["speechify", "elevenlabs"] : ["elevenlabs", "speechify"]
        }
        if has(tok, notOurs) { return [] }
        if (24...256).contains(tok.count), tok.contains(where: { $0.isNumber }), tok.contains(where: { $0.isLetter }) {
            var shaped: [String] = []
            if full(tok, hex64) { shaped = ["soniox"] }
            else if full(tok, hex40) { shaped = ["deepgram"] }
            else if full(tok, hex32) { shaped = ["assemblyai"] }
            else if full(tok, alnum32), tok.contains(where: { $0.isUppercase }), tok.contains(where: { $0.isLowercase }) { shaped = ["speechmatics"] }
            var out: [String] = []
            for k in h.filter({ $0 != "google" && $0 != "anthropic" }) + shaped where !out.contains(k) { out.append(k) }
            return out
        }
        return []
    }

    /// A Google service account file as one line, only when it holds what OAuth needs.
    static func serviceAccount(_ text: String) -> String? {
        guard let d = text.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              o["type"] as? String == "service_account", let email = o["client_email"] as? String, !email.isEmpty,
              let pk = o["private_key"] as? String, pk.contains("PRIVATE KEY") else { return nil }
        let slim: [String: Any] = ["client_email": email, "private_key": pk, "project_id": o["project_id"] as? String ?? "",
                                   "token_uri": o["token_uri"] as? String ?? "https://oauth2.googleapis.com/token"]
        guard let out = try? JSONSerialization.data(withJSONObject: slim) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    static func scan(_ fileName: String, _ text: String) -> [Cand] {
        if let sa = serviceAccount(text) { return [Cand(value: sa, kinds: ["serviceaccount"])] }
        let name = fileName.lowercased()
        let lines = text.components(separatedBy: "\n")
        var toks: [(value: String, kinds: [String])] = []
        let trim = CharacterSet(charactersIn: ".-_")
        for (i, line) in lines.enumerated() {
            let prev = i == 0 ? "" : lines[i - 1].trimmingCharacters(in: .whitespaces)
            let prevHasKey = prev.components(separatedBy: separators).contains { !tokenKinds($0.trimmingCharacters(in: trim), name).isEmpty }
            let ctx = (name + " " + (prev.isEmpty || prevHasKey ? "" : prev) + " " + line).lowercased()
            for raw in line.components(separatedBy: separators) {
                let t = raw.trimmingCharacters(in: trim)
                if t.isEmpty || t == "DELETED" { continue }
                let k = tokenKinds(t, ctx)
                if !k.isEmpty { toks.append((t, k)) }
            }
        }
        var out: [String: Cand] = [:], order: [String] = []
        func put(_ key: String, _ c: Cand) { if out[key] == nil { order.append(key) }; out[key] = c }
        // Cloudflare is two parts, an account id (32 hex) and a token (cfat_/cfut_ or any token in a Cloudflare file)
        let cfFile = name.contains("cloudflare") || text.lowercased().contains("cloudflare") || toks.contains { $0.kinds == ["cftoken"] }
        var taken = Set<String>()
        if cfFile {
            let acct = toks.first { full($0.value, hex32) }?.value
            let token = toks.first { $0.kinds == ["cftoken"] }?.value
                ?? toks.first { $0.value != acct && $0.value.count >= 30 && !full($0.value, hex32) &&
                                !$0.kinds.contains { k in k == "groq" || k == "google" || k == "anthropic" } }?.value
            if let acct, let token {
                put("cf:\(acct):\(token)", Cand(value: acct + "\n" + token, kinds: ["cloudflare"]))
                taken.insert(acct); taken.insert(token)
            }
        }
        for t in toks where !taken.contains(t.value) && t.kinds != ["cftoken"] { put(t.value, Cand(value: t.value, kinds: t.kinds)) }
        return order.compactMap { out[$0] }
    }
}

// MARK: the free test (spend rule: a list or an auth call, never a message or a transcription)

enum KeyTest {
    static func rate(_ code: Int, _ body: String) -> KStatus {
        let low = body.lowercased()
        switch code {
        case 200...299: return .working
        case 429: return .limited
        case 402: return .noBalance
        case 401: return .dead
        case 403: return low.contains("balance") || low.contains("credit") || low.contains("insufficient") ? .noBalance : .dead
        case 400 where low.contains("api key not valid") || low.contains("api_key_invalid"): return .dead
        default: return .network
        }
    }

    static func get(_ url: String, _ headers: [String: String]) -> KStatus {
        var r = URLRequest(url: URL(string: url)!)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let a = call(r, timeout: 12)
        if a.status == 0 { return .network }
        return rate(a.status, String(data: a.data, encoding: .utf8) ?? "")
    }

    /// kind: groq, anthropic, assemblyai, deepgram, elevenlabs, speechmatics, soniox, gemini, google_v1, cloudflare, google_chirp
    static func test(_ kind: String, _ v: String) -> KStatus {
        var s = once(kind, v)
        if s == .network { s = once(kind, v) }
        return s
    }

    static func once(_ kind: String, _ v: String) -> KStatus {
        switch kind {
        case "groq": return get("https://api.groq.com/openai/v1/models", ["Authorization": "Bearer " + v])
        case "anthropic": return get("https://api.anthropic.com/v1/models", ["x-api-key": v, "anthropic-version": "2023-06-01"])
        case "assemblyai": return get("https://api.assemblyai.com/v2/transcript?limit=1", ["authorization": v])
        case "deepgram": return get("https://api.deepgram.com/v1/projects", ["Authorization": "Token " + v])
        case "elevenlabs": return get("https://api.elevenlabs.io/v1/user", ["xi-api-key": v])
        case "speechmatics": return get("https://asr.api.speechmatics.com/v2/jobs?limit=1", ["Authorization": "Bearer " + v])
        case "soniox": return get("https://api.soniox.com/v1/files", ["Authorization": "Bearer " + v])
        case "gemini": return get("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1", ["x-goog-api-key": v])
        case "google_v1": return speechV1(v)
        case "cloudflare":
            let l = v.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard l.count >= 2 else { return .dead }
            let a = get("https://api.cloudflare.com/client/v4/accounts/\(l[0])/tokens/verify", ["Authorization": "Bearer " + l[1]])
            if a == .working || a == .network { return a }
            return get("https://api.cloudflare.com/client/v4/user/tokens/verify", ["Authorization": "Bearer " + l[1]])
        case "google_chirp":
            switch Chirp.token(v) {
            case .success: return .working
            case .failure(let e): return e.message.contains("network") ? .network : .dead
            }
        default: return .network
        }
    }

    /// Google Speech v1 with an empty audio field: 400 means the key is valid and the API on, 403 that the API is off. No audio, no billing.
    static func speechV1(_ k: String) -> KStatus {
        var r = URLRequest(url: URL(string: "https://speech.googleapis.com/v1/speech:recognize")!)
        r.httpMethod = "POST"
        r.setValue(k, forHTTPHeaderField: "x-goog-api-key"); r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = Data(#"{"config":{"languageCode":"en-US"},"audio":{"content":""}}"#.utf8)
        let a = call(r, timeout: 12)
        if a.status == 0 { return .network }
        let low = (String(data: a.data, encoding: .utf8) ?? "").lowercased()
        if a.status == 400 && !(low.contains("api key not valid") || low.contains("api_key_invalid")) { return .working }
        if (200...299).contains(a.status) { return .working }
        if a.status == 429 { return .limited }
        return .dead
    }

    static func verdict(_ s: KStatus) -> Verdict {
        switch s { case .working: return .ok; case .limited: return .cool; case .dead: return .dead; case .noBalance: return .noCredit; case .network: return .soft }
    }

    static func word(_ v: Verdict) -> String {
        switch v { case .ok: return "works"; case .dead: return "rejected"; case .noCredit: return "no credit"; case .cool: return "throttled"; case .soft: return "unclear" }
    }

    static func good(_ s: KStatus) -> Bool { s == .working || s == .limited }

    /// the ring a kind's keys live in
    static func testKind(_ p: Provider) -> String {
        switch p {
        case .google: return "google_v1"
        case .chirp: return "google_chirp"
        default: return p.rawValue
        }
    }
}

// MARK: the import

enum KeyImporter {
    static let rejectedFile = Keys.folder.appendingPathComponent("rejected.json")

    static func fingerprint(_ s: String) -> String { String(SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)) }
    static func loadRejected() -> Set<String> {
        Set((try? Data(contentsOf: rejectedFile)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }
    static func saveRejected(_ s: Set<String>) {
        guard let d = try? JSONEncoder().encode(Array(s)) else { return }
        try? d.write(to: rejectedFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rejectedFile.path)
    }

    static func provider(_ kind: String) -> Provider? {
        switch kind {
        case "groq": return .groq
        case "gemini": return .gemini
        case "google_v1": return .google
        case "deepgram": return .deepgram
        case "assemblyai": return .assemblyai
        case "speechmatics": return .speechmatics
        case "soniox": return .soniox
        case "elevenlabs": return .elevenlabs
        case "anthropic": return .anthropic
        case "cloudflare": return .cloudflare
        case "serviceaccount", "google_chirp": return .chirp
        default: return nil
        }
    }

    final class Group {
        let title: String
        var keys = 0, working = 0, limited = 0, dead = 0, noBalance = 0, unreached = 0, held = 0
        init(_ t: String) { title = t }
        func line() -> String {
            var parts = ["\(keys) tested", "\(working) working"]
            if limited > 0 { parts.append("\(limited) rate-limited for now") }
            if dead > 0 { parts.append("\(dead) refused") }
            if noBalance > 0 { parts.append("no balance") }
            if unreached > 0 { parts.append("\(unreached) not reached") }
            if held > 0 { parts.append("\(held) already held") }
            return title + ": " + parts.joined(separator: ", ")
        }
    }

    /// Files in, sentence out. `skipRejected`: the by-itself import at launch does not ask again about a key that failed before.
    static func importTexts(_ files: [(name: String, text: String)], skipRejected: Bool, source: String = "file") -> String {
        var seen = Set<String>()
        let cands = files.flatMap { KeyScan.scan($0.name, $0.text).map { c in (c, $0.name) } }.filter { seen.insert($0.0.value).inserted }
        if cands.isEmpty { return "No keys found in \(files.count) file(s)." }
        var held = Set<String>()
        for p in Provider.allCases { for k in Keys.entries(p) { held.insert(k.key) } }
        var rejected = loadRejected()
        let todo = cands.filter { c in !held.contains(c.0.value) && !(skipRejected && rejected.contains(fingerprint(c.0.value))) }
        let already = cands.count - todo.count
        // each new key asks its one free question, a few at a time; the answers are put back in file order
        struct Res { var kind: String; var status: KStatus; var gem: KStatus?; var sp: KStatus?; var isGoogle: Bool }
        var results = [Res?](repeating: nil, count: todo.count)
        let q = DispatchQueue(label: "keyimport"), group = DispatchGroup(), gate = DispatchSemaphore(value: 6)
        for (i, item) in todo.enumerated() {
            group.enter(); gate.wait()
            DispatchQueue.global().async {
                let cand = item.0
                var r: Res
                if cand.kinds.first == "google" {
                    let gem = KeyTest.test("gemini", cand.value), sp = KeyTest.test("google_v1", cand.value)
                    r = Res(kind: "google", status: KeyTest.good(gem) ? gem : sp, gem: gem, sp: sp, isGoogle: true)
                } else {
                    var kind = cand.kinds.first ?? "", status = KStatus.dead
                    for (n, k) in cand.kinds.enumerated() {
                        let ring = k == "serviceaccount" ? "google_chirp" : k
                        if k == "speechify" { status = .dead; continue }
                        let s = KeyTest.test(ring, cand.value)
                        if n == 0 { status = s }
                        if KeyTest.good(s) || s == .noBalance { kind = k; status = s; break }
                    }
                    r = Res(kind: kind, status: status, gem: nil, sp: nil, isGoogle: false)
                }
                q.sync { results[i] = r }
                gate.signal(); group.leave()
            }
        }
        group.wait()
        var groups: [String: Group] = [:], groupOrder: [String] = []
        func g(_ k: String, _ title: String) -> Group {
            if let x = groups[k] { return x }
            let x = Group(title); groups[k] = x; groupOrder.append(k); return x
        }
        var keep: [Provider: [KeyEntry]] = [:]
        for (i, item) in todo.enumerated() {
            guard let r = results[i] else { continue }
            let cand = item.0, base = (item.1 as NSString).deletingPathExtension
            func add(_ p: Provider) { keep[p, default: []].append(KeyEntry(key: cand.value, title: base)) }
            if r.isGoogle {
                let grp = g("google", "Google")
                grp.keys += 1
                if let gem = r.gem, KeyTest.good(gem) { add(.gemini) }
                if let sp = r.sp, KeyTest.good(sp) { add(.google) }
                if r.gem == .working || r.sp == .working { grp.working += 1 }
                else if KeyTest.good(r.gem ?? .dead) || KeyTest.good(r.sp ?? .dead) { grp.working += 1; grp.limited += 1 }
                else if r.gem == .network && r.sp == .network { grp.unreached += 1 }
                else { grp.dead += 1; rejected.insert(fingerprint(cand.value)) }
                continue
            }
            guard let p = provider(r.kind) else { rejected.insert(fingerprint(cand.value)); continue }
            let grp = g(r.kind == "serviceaccount" ? "google_chirp" : r.kind, p.title)
            grp.keys += 1
            switch r.status {
            case .working: grp.working += 1; add(p)
            case .limited: grp.working += 1; grp.limited += 1; add(p)
            case .noBalance: grp.noBalance += 1; rejected.insert(fingerprint(cand.value))
            case .network: grp.unreached += 1
            case .dead: grp.dead += 1; rejected.insert(fingerprint(cand.value))
            }
        }
        var stored = 0
        for (p, list) in keep {
            if p == .cloudflare || p == .chirp { Keys.set(p, [list[0]]); stored += 1 }       // one account each: replaced
            else { stored += Keys.add(p, list) }
        }
        saveRejected(rejected)
        if keep[.anthropic] != nil || keep[.assemblyai] != nil { Ring.revive(.anthropic); Ring.revive(.assemblyai) }
        let lines = groupOrder.compactMap { groups[$0]?.line() }
        var tail = "Stored \(stored) new working key(s)."
        if already > 0 { tail += " \(already) already held or refused before (not asked again)." }
        appendLog("keys (\(source)): " + (lines + [tail]).joined(separator: "; "))
        return (lines + [tail]).joined(separator: "\n")
    }

    static func importFiles(_ urls: [URL]) -> String {
        var files: [(name: String, text: String)] = [], skipped = 0
        for u in urls {
            let ext = u.pathExtension.lowercased()
            guard ["txt", "json", "env", "csv", "conf", "cfg", "ini", "md", "key", ""].contains(ext),
                  let t = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1)) else { skipped += 1; continue }
            files.append((u.lastPathComponent, String(t.prefix(2_000_000))))
        }
        var s = files.isEmpty ? "" : importTexts(files, skipRejected: false)
        if skipped > 0 { s += (s.isEmpty ? "" : "\n") + "\(skipped) file(s) skipped: text files only (.txt, .json, .env)." }
        return s
    }

    /// Re-tests every held key; the ones that no longer work are dropped, the unreachable kept.
    static func retest() -> String {
        var out: [String] = [], removed = 0
        let q = DispatchQueue(label: "retest")
        for p in Provider.allCases {
            let list = Keys.entries(p)
            if list.isEmpty { continue }
            var verdicts = [KStatus?](repeating: nil, count: list.count)
            let group = DispatchGroup(), gate = DispatchSemaphore(value: 6)
            for (i, k) in list.enumerated() {
                group.enter(); gate.wait()
                DispatchQueue.global().async {
                    let s = KeyTest.test(KeyTest.testKind(p), k.key)
                    q.sync { verdicts[i] = s }
                    gate.signal(); group.leave()
                }
            }
            group.wait()
            var keep: [KeyEntry] = [], w = 0, bad = 0, unreached = 0
            for (i, k) in list.enumerated() {
                let s = verdicts[i] ?? .network
                if KeyTest.good(s) { w += 1; keep.append(k); Ring.mark(p, k, KeyTest.verdict(s), "works", rest: s == .limited ? 60 : nil) }
                else if s == .network { unreached += 1; keep.append(k) }
                else { bad += 1 }
            }
            if bad > 0 { removed += bad; Keys.set(p, keep); Ring.reset(p) }
            out.append("\(p.title): \(list.count) tested, \(w) working" + (bad > 0 ? ", \(bad) removed" : "") + (unreached > 0 ? ", \(unreached) not reached" : ""))
        }
        if out.isEmpty { return "No keys held yet. Import a file first." }
        saveRejected([])
        let sentence = (out + ["Removed \(removed) key(s) that no longer work."]).joined(separator: "\n")
        appendLog("re-test keys: " + sentence.replacingOccurrences(of: "\n", with: "; "))
        return sentence
    }

    // v13: on his Mac the key notes in ~/Downloads/API come in by themselves, at every launch and every time ⚙ opens:
    // only the files whose name says a speech or Claude provider are read (the folder holds other secrets: never opened).
    static let famous = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/API")
    static let words = ["groq", "deepgram", "assembly", "speechmatics", "soniox", "eleven", "gemini", "google-stt", "google_stt",
                        "cloudflare-workers", "claude", "anthropic", "haiku"]
    static var busy = false
    @discardableResult
    static func loadFamous() -> String {
        if busy { return "" }
        busy = true; defer { busy = false }
        let urls = ((try? FileManager.default.contentsOfDirectory(at: famous, includingPropertiesForKeys: nil)) ?? []).filter { u in
            ["txt", "json"].contains(u.pathExtension.lowercased()) && words.contains { u.lastPathComponent.lowercased().contains($0) }
        }
        var files: [(name: String, text: String)] = []
        for u in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let t = try? String(contentsOf: u, encoding: .utf8) { files.append((u.lastPathComponent, t)) }
        }
        if files.isEmpty { return "" }
        let r = importTexts(files, skipRejected: true, source: "~/Downloads/API")
        return r.contains("tested") ? r : ""
    }
}
