// The shared correction database (v50): one private GitHub data repository, written by TTT on the phones and by Vox here.
//
// Marko, 17.11.2026: "please make phone and this app write to same GitHub data repository so the databases can be shared
// for corrections, and it learns from my mistakes."
//
// Repository markoboskoauroville/MANTRA_CORRECTIONS (its TAKEOVER.md is the format):
//   pairs.json              the curated table (TTT's dictation_corrections.json)
//   learned/<source>.jsonl  append-only lines {id, from, to, lang, source, kind, count, enabled, updated};
//                           each device writes ONLY its own file (this Mac: learned/mac.jsonl), so a push never loses another's
// Merge = union: per id the newest line's `to` wins, the counts of the devices that agree are added, a rule is applied when
// it is his own or was made twice (TTT's ACTIVE_AT). Pulled at start and every five minutes; what is learned here is appended
// to the local mac.jsonl at once (that file is the queue) and pushed when GitHub can be reached.
// The token comes from a key file (~/Downloads/API/github_token.txt), else from the gh command; it is never shown or logged.
import Foundation
import CryptoKit
import ApplicationServices

enum Shared {
    static let repo = "markoboskoauroville/MANTRA_CORRECTIONS"
    static let source = "mac"
    static var dir: URL { appSupport.appendingPathComponent("corrections") }
    static var own: URL { dir.appendingPathComponent("learned/\(source).jsonl") }

    private static let lock = NSLock()
    private static var _rules: [CorrectionRules.Rule] = []
    private static var _table = SpellingTable()
    private static var loaded = false
    private static let queue = DispatchQueue(label: "shared-corrections", qos: .utility)
    private static var timer: DispatchSourceTimer?
    static var status = "not synced yet"

    static var rules: [CorrectionRules.Rule] { ensure(); lock.lock(); defer { lock.unlock() }; return _rules }
    static var table: SpellingTable { ensure(); lock.lock(); defer { lock.unlock() }; return _table }
    private static func ensure() { lock.lock(); let l = loaded; lock.unlock(); if !l { load() } }

    // MARK: lines

    struct Line {
        var id: String, from: String, to: String, lang: String, source: String, kind: String, count: Int, enabled: Bool, updated: String
        init?(_ json: String) {
            guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let from = o["from"] as? String, let to = o["to"] as? String, !from.isEmpty, !to.isEmpty else { return nil }
            let lg = (o["lang"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "*"
            self.from = from; self.to = to; lang = lg
            id = (o["id"] as? String) ?? CorrectionRules.keyOf(from, lg)
            source = o["source"] as? String ?? "?"
            kind = o["kind"] as? String ?? "learned"
            count = (o["count"] as? NSNumber)?.intValue ?? 0
            enabled = o["enabled"] as? Bool ?? true
            updated = o["updated"] as? String ?? ""
        }
        init(rule r: CorrectionRules.Rule, count: Int) {
            id = r.key; from = r.wrong; to = r.right; lang = r.language; source = Shared.source
            kind = r.mine ? "mine" : "learned"; self.count = count; enabled = r.enabled; updated = r.updated
        }
        var json: String {
            let o: [String: Any] = ["id": id, "from": from, "to": to, "lang": lang, "source": source, "kind": kind, "count": count, "enabled": enabled, "updated": updated]
            guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
            return String(data: d, encoding: .utf8) ?? ""
        }
    }

    static func lines(_ url: URL) -> [Line] {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return t.split(separator: "\n").compactMap { Line(String($0)) }
    }

    /// the union: per file the last line of an id is that device's state; across files the newest `to` wins and the counts
    /// of the devices that agree on it are added
    static func merge(_ files: [[Line]]) -> [CorrectionRules.Rule] {
        var byId: [String: [Line]] = [:], order: [String] = []
        for file in files {
            var last: [String: Line] = [:], seen: [String] = []
            for l in file { if last[l.id] == nil { seen.append(l.id) }; last[l.id] = l }
            for id in seen { if byId[id] == nil { order.append(id) }; byId[id, default: []].append(last[id]!) }
        }
        return order.compactMap { id in
            guard let all = byId[id], let newest = all.max(by: { $0.updated < $1.updated }) else { return nil }
            let agree = all.filter { $0.to == newest.to }
            return CorrectionRules.Rule(wrong: newest.from, right: newest.to, language: newest.lang, count: agree.reduce(0) { $0 + $1.count },
                                        enabled: newest.enabled, mine: agree.contains { $0.kind == "mine" }, updated: newest.updated)
        }
    }

    // MARK: the local copy

    static func load() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir.appendingPathComponent("learned"), withIntermediateDirectories: true)
        let files = ((try? fm.contentsOfDirectory(at: dir.appendingPathComponent("learned"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let rules = merge(files.map(lines))
        // the table: the repository's copy, or the hub's own file on this Mac when that one is newer
        var table = SpellingTable()
        for url in [dir.appendingPathComponent("pairs.json"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/API/dictation_corrections.json")] {
            if let d = try? Data(contentsOf: url), let t = SpellingTable.parse(d), t.updated >= table.updated || table.pairs.isEmpty { table = t }
        }
        lock.lock(); _rules = rules; _table = table; loaded = true; lock.unlock()
    }

    static func stamp() -> String { let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); return f.string(from: Date()) }

    private static func append(_ new: [Line]) {
        guard !new.isEmpty else { return }
        try? FileManager.default.createDirectory(at: own.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: own, encoding: .utf8)) ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += new.map(\.json).filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
        try? text.write(to: own, atomically: true, encoding: .utf8)
    }

    /// corrections he made in a box after a take (Learner), counted and kept; applied by themselves from the second time
    static func learn(_ swaps: [CorrectionRules.Swap], lang: String) {
        guard !swaps.isEmpty else { return }
        let now = stamp()
        var mine: [String: Line] = [:]
        for l in lines(own) { mine[l.id] = l }
        var out: [Line] = []
        var all = rules
        for s in swaps {
            let (next, changed) = CorrectionRules.record(all, s, lang, now: now)
            all = next
            for r in changed {
                // this device's own running total of this fix (the merged count is the sum over the devices)
                let was = mine[r.key]
                let n = r.enabled ? ((was?.to == r.right ? was!.count : 0) + 1) : (was?.count ?? 0)
                let line = Line(rule: r, count: n)
                mine[r.key] = line
                out.append(line)
            }
        }
        append(out)
        load()
        appendLog("corrections: learned \(swaps.count) from the last take (\(swaps.map { "\($0.wrong) → \($0.right)" }.joined(separator: ", ")))")
        queue.asyncAfter(deadline: .now() + 2) { sync() }
    }

    /// a rule of his own, a rule at once (the test hook and, later, a settings page)
    static func addMine(_ wrong: String, _ right: String, lang: String = "*") {
        let w = wrong.trimmingCharacters(in: .whitespaces), r = right.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !r.isEmpty, w != r else { return }
        append([Line(rule: CorrectionRules.Rule(wrong: w, right: r, language: lang, count: 0, enabled: true, mine: true, updated: stamp()), count: 0)])
        load()
        queue.async { sync() }
    }
    static func switchOff(_ wrong: String, lang: String) {
        guard var r = rules.first(where: { $0.key == CorrectionRules.keyOf(wrong, lang) }) else { return }
        r.enabled = false; r.updated = stamp()
        append([Line(rule: r, count: 0)])
        load()
        queue.async { sync() }
    }

    // MARK: GitHub

    private static var cachedToken: String?
    /// a token that can read this repository: the key file first, then the gh command's own login; never logged
    private static func token() -> String? {
        if let t = cachedToken { return t }
        var candidates: [String] = []
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/API/github_token.txt")
        if let t = try? String(contentsOf: file, encoding: .utf8), let re = try? NSRegularExpression(pattern: "(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|gho_[A-Za-z0-9]{30,})") {
            let ns = t as NSString
            candidates += re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
        for gh in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: gh) {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: gh); p.arguments = ["auth", "token"]
            p.standardOutput = pipe; p.standardError = Pipe()
            if (try? p.run()) != nil {
                p.waitUntilExit()
                let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !s.isEmpty { candidates.append(s) }
            }
            break
        }
        for c in candidates {
            if let (code, _) = call("GET", "", token: c), code == 200 { cachedToken = c; return c }
        }
        return nil
    }

    private static func call(_ method: String, _ path: String, token: String, body: Data? = nil, raw: Bool = false) -> (Int, Data)? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)" + path) else { return nil }
        // never the URL cache: GitHub lets an answer be reused for 60 s, and a stale tree gives a stale sha (the second push of v50 was refused)
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        r.httpMethod = method
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(raw ? "application/vnd.github.raw" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("VoxToTxt", forHTTPHeaderField: "User-Agent")
        r.httpBody = body
        let sem = DispatchSemaphore(value: 0)
        var out: (Int, Data)?
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            if let h = resp as? HTTPURLResponse { out = (h.statusCode, d ?? Data()) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 25)
        return out
    }

    static func blobSha(_ data: Data) -> String {
        var d = Data("blob \(data.count)\0".utf8); d.append(data)
        return Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    private static var syncing = false
    /// pull what the other devices learned, push what this Mac learned (called on the queue; safe to call any time)
    static func sync() {
        if syncing { return }
        syncing = true; defer { syncing = false }
        guard let tok = token() else { status = "no GitHub token: corrections stay on this Mac"; appendLog("shared corrections: " + status); return }
        guard let (code, data) = call("GET", "/git/trees/main?recursive=1", token: tok), code == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tree = o["tree"] as? [[String: Any]] else {
            status = "GitHub not reached: what was learned waits on this Mac"; return
        }
        var remote: [String: String] = [:]
        for t in tree { if let p = t["path"] as? String, let s = t["sha"] as? String, t["type"] as? String == "blob" { remote[p] = s } }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir.appendingPathComponent("learned"), withIntermediateDirectories: true)
        var pulled = 0, pushed = false
        let ownPath = "learned/\(source).jsonl"
        for (path, sha) in remote where path == "pairs.json" || (path.hasPrefix("learned/") && path.hasSuffix(".jsonl") && path != ownPath) {
            let local = dir.appendingPathComponent(path)
            if let d = try? Data(contentsOf: local), blobSha(d) == sha { continue }
            if let (c, d) = call("GET", "/contents/" + path, token: tok, raw: true), c == 200 { try? d.write(to: local, options: .atomic); pulled += 1 }
        }
        // this Mac's own file: the union of the remote lines (after a reinstall) and the local ones, then pushed when it differs
        var localData = (try? Data(contentsOf: own)) ?? Data()
        if let sha = remote[ownPath], blobSha(localData) != sha, let (c, d) = call("GET", "/contents/" + ownPath, token: tok, raw: true), c == 200 {
            let remoteLines = String(data: d, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
            let localLines = String(data: localData, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
            let have = Set(remoteLines)
            let union = remoteLines + localLines.filter { !have.contains($0) }
            if union.count != localLines.count || union != localLines {
                let text = union.isEmpty ? "" : union.joined(separator: "\n") + "\n"
                try? text.write(to: own, atomically: true, encoding: .utf8)
                localData = Data(text.utf8)
            }
        }
        if blobSha(localData) != (remote[ownPath] ?? "") {
            var body: [String: Any] = ["message": "Vox to Txt on the Mac: learned corrections", "content": localData.base64EncodedString(), "branch": "main"]
            if let sha = remote[ownPath] { body["sha"] = sha }
            if let b = try? JSONSerialization.data(withJSONObject: body), let (c, _) = call("PUT", "/contents/" + ownPath, token: tok, body: b), c == 200 || c == 201 { pushed = true }
            else { status = "push refused: it waits on this Mac"; appendLog("shared corrections: " + status) }
        }
        load()
        let n = rules.count
        status = "synced \(stamp()): \(n) rules, \(table.pairs.count) pairs"
        if pulled > 0 || pushed { appendLog("shared corrections: pulled \(pulled) file(s)\(pushed ? ", pushed this Mac's" : ""); \(n) rules, \(table.pairs.count) pairs") }
    }

    /// at launch: the local copy at once, the repository in the background, then every five minutes
    static func start() {
        load()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 300)
        t.setEventHandler { sync(); Lexicon.unloadIfIdle() }
        t.resume()
        timer = t
        Learner.start()
    }
}

// MARK: learning from what he corrects in the box (TTT's MaDictationCorrections: noteDictation, settle)

enum Learner {
    private struct Pending {
        let text: String
        let element: AXUIElement
        let lang: String
        var before: String?          // the 24 characters in front of the take, when the box could be read
        var snapshot: String?        // the take's stretch of the box as it was last seen still resembling the take
        let at: Date
    }
    private static var pending: Pending?
    private static let queue = DispatchQueue(label: "learner", qos: .utility)
    private static var timer: DispatchSourceTimer?
    static var enabled: Bool { UserDefaults.standard.object(forKey: "learnCorrections") as? Bool ?? true }

    static func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 4)
        t.setEventHandler { look() }
        t.resume()
        timer = t
    }

    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{200B}", with: "") }

    /// a take has just been typed into `element`: remember it as it went in, and where
    static func note(_ text: String, element: AXUIElement, lang: String) {
        queue.async {
            settleNow()
            let t = plain(text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard enabled, Fix.on, !t.isEmpty, !Writer.isTerminal(element), CorrectionRules.tokenize(t).count >= 2 else { pending = nil; return }
            var p = Pending(text: t, element: element, lang: lang, before: nil, snapshot: nil, at: Date())
            if let v = Writer.value(element).map(plain), let r = v.range(of: t, options: .backwards) { p.before = String(v[..<r.lowerBound].suffix(24)) }
            pending = p
        }
    }

    /// the stretch of the box that began where the take was written
    private static func region(_ p: Pending) -> String? {
        AXUIElementSetMessagingTimeout(p.element, 0.4)
        guard let all = Writer.value(p.element).map(plain), !all.isEmpty else { return nil }
        var start: String.Index?
        if let b = p.before {
            if b.isEmpty { start = all.startIndex } else if let r = all.range(of: b, options: .backwards) { start = r.upperBound }
        }
        if start == nil {
            // the words in front are not known or are gone: the take's own first words say where it is
            let head = String(p.text.prefix(12))
            if let r = all.range(of: head, options: .backwards) { start = r.lowerBound }
        }
        guard let s = start else { return nil }
        return String(all[s...].prefix(p.text.count + 80))
    }

    private static func resembles(_ written: String, _ now: String) -> Bool {
        let a = Set(CorrectionRules.tokenize(written).map(\.text)), b = Set(CorrectionRules.tokenize(now).map(\.text))
        return !a.isEmpty && a.intersection(b).count * 2 >= a.count
    }

    /// every few seconds: the box is read again while it still holds the take (a message that is sent empties the box:
    /// the last look before that is what he made of it)
    private static func look() {
        guard var p = pending else { return }
        if Date().timeIntervalSince(p.at) > 900 { settleNow(); return }
        if let r = region(p), resembles(p.text, r) { p.snapshot = r; pending = p }
    }

    /// once per take: when the next take is about to be typed, or after a quarter of an hour
    static func settle() { queue.async { settleNow() } }
    private static func settleNow() {
        guard let p = pending else { return }
        pending = nil
        guard enabled else { return }
        var now = p.snapshot
        if let r = region(p), resembles(p.text, r) { now = r }
        guard let n = now else { return }
        let swaps = CorrectionRules.diff(p.text, n)
        if !swaps.isEmpty { Shared.learn(swaps, lang: p.lang == "auto" ? "*" : p.lang) }
    }
}
